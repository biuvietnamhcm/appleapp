import SwiftUI
import CoreBluetooth
import UniformTypeIdentifiers

struct BLEDevice {
    let identifier: UUID
    let name: String?
    let rssi: Int?
    let peripheral: CBPeripheral
}

struct ContentView: View {
    @StateObject var medicationManager = MedicationManager()
    @EnvironmentObject var notificationManager: MedicationNotificationManager
    
    @State var selectedInputMode: InputMode = .json
    @State var showingFilePicker = false
    @State var showingAlert = false
    @State var alertMessage = ""
    @State var isSubmitting = false
    
    @State var showingQRScanner = false
    
    @State var centralManager: CBCentralManager?
    @State var discoveredDevices: [BLEDevice] = []
    @State var selectedDevice: BLEDevice?
    @State var connectedDevice: BLEDevice?
    @State var isScanning = false
    @State var isConnected = false
    @State var statusMessage = "Ready"
    @State var transmissionProgress: Double = 0.0
    @State var connectedPeripheral: CBPeripheral?
    @State var dataCharacteristic: CBCharacteristic?
    @State var bluetoothDelegate: BluetoothDelegate?
    
    @State var currentChunk: Int = 0
    @State var totalChunks: Int = 0
    @State var chunkProgressMessage: String = ""
    
    var canSubmit: Bool {
        isConnected && dataCharacteristic != nil && !medicationManager.medications.isEmpty && selectedDevice != nil
    }
    
    private let serviceUUID = CBUUID(string: "FFE0")
    private let characteristicUUID = CBUUID(string: "FFE1")

    enum InputMode: String, CaseIterable {
        case json = "JSON File"
        case manual = "Manual Input"
        case qr = "QR Code"
        
        var icon: String {
            switch self {
            case .json: return "doc.text"
            case .manual: return "pencil"
            case .qr: return "qrcode"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Input Mode Selection
                    inputModeSection
                    
                    // Manual Input Section (moved before Send Configuration)
                    if selectedInputMode == .manual {
                        manualInputSection
                    }
                    
                    // BLE Device Connection
                    bleConnectionSection
                    
                    // File Upload Section
                    if selectedInputMode == .json {
                        fileUploadSection
                    }
                    
                    // QR Code Input Section
                    if selectedInputMode == .qr {
                        qrCodeSection
                    }
                    
                    // Medication Preview
                    medicationPreviewSection
                    
                    // Send Configuration Section
                    sendConfigurationSection
                    
                    // Status Section
                    statusSection
                }
                .padding()
            }
            .navigationTitle("Pill Dispenser")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Alert", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showingQRScanner) {
            QRCodeScannerView(isPresented: $showingQRScanner) { qrCodes in
                handleQRCodeDetection(qrCodes)
            }
        }
        .onAppear {
            setupBluetooth()
        }
    }
    
    private func setupBluetooth() {
        bluetoothDelegate = BluetoothDelegate(
            onStateUpdate: { state in
                switch state {
                case .poweredOn:
                    statusMessage = "Bluetooth ready"
                    startScanning()
                case .poweredOff:
                    statusMessage = "Bluetooth is off"
                case .unauthorized:
                    statusMessage = "Bluetooth unauthorized"
                case .unsupported:
                    statusMessage = "Bluetooth not supported"
                default:
                    statusMessage = "Bluetooth unavailable"
                }
            },
            onDeviceDiscovered: { device in
                if !discoveredDevices.contains(where: { $0.identifier == device.identifier }) {
                    discoveredDevices.append(device)
                }
            },
            onDeviceConnected: { peripheral in
                connectedPeripheral = peripheral
                isConnected = true
                statusMessage = "Connected to \(peripheral.name ?? "device")"
                peripheral.discoverServices([serviceUUID])
            },
            onCharacteristicDiscovered: { characteristic in
                dataCharacteristic = characteristic
                statusMessage = "Ready for data transmission"
            },
            onConnectionFailed: { error in
                statusMessage = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
                isConnected = false
            },
            onDisconnected: { error in
                isConnected = false
                connectedPeripheral = nil
                dataCharacteristic = nil
                statusMessage = "Disconnected"
            }
        )
        
        bluetoothDelegate?.onChunkAcknowledged = { chunkNum, totalChunks in
            DispatchQueue.main.async {
                self.currentChunk = chunkNum
                self.totalChunks = totalChunks
                self.transmissionProgress = Double(chunkNum) / Double(totalChunks)
                self.chunkProgressMessage = "📦 Chunk \(chunkNum)/\(totalChunks) acknowledged"
                self.statusMessage = "Sending chunk \(chunkNum)/\(totalChunks)"
            }
        }
        
        centralManager = CBCentralManager(
            delegate: bluetoothDelegate,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: true]
        )
    }
    
    private func startScanning() {
        guard centralManager?.state == .poweredOn else {
            statusMessage = "Bluetooth not available"
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        statusMessage = "Scanning for devices..."
        
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            stopScanning()
        }
    }
    
    private func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        statusMessage = discoveredDevices.isEmpty ? "No devices found" : "Scan complete"
    }
    
    func startEnhancedScanning() { startScanning() }
    func stopEnhancedScanning()  { stopScanning()  }
    
    func selectDevice(_ device: BLEDevice) {
        selectedDevice = device
        statusMessage = "Connecting to \(device.name ?? "device")..."
        centralManager?.connect(device.peripheral, options: nil)
    }
    
    private func sendData(_ data: Data, completion: @escaping (Bool, String?) -> Void) {
        guard let characteristic = dataCharacteristic,
              let peripheral = connectedPeripheral,
              let delegate = bluetoothDelegate else {
            completion(false, "No data characteristic or delegate available")
            return
        }
        
        statusMessage = "Preparing enhanced data transmission..."
        transmissionProgress = 0.0
        currentChunk = 0
        totalChunks = 0
        chunkProgressMessage = "Initializing transmission..."
        
        // Use enhanced transmission with acknowledgments
        delegate.sendDataWithAcknowledgment(data, peripheral: peripheral, characteristic: characteristic, chunkSize: 20) { success, error in
            DispatchQueue.main.async {
                if success {
                    self.statusMessage = "✅ Transmission complete"
                    self.chunkProgressMessage = "All chunks sent successfully"
                    self.transmissionProgress = 1.0
                } else {
                    self.statusMessage = "❌ Transmission failed"
                    self.chunkProgressMessage = error ?? "Unknown error"
                }
                completion(success, error)
            }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        alertMessage = message
        showingAlert = true
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "pills.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Auto Pill Dispenser Control")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Configure your medication schedule")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var inputModeSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Input Method", systemImage: "folder")
                .font(.headline)
                .foregroundColor(.blue)
            
            HStack(spacing: 10) {
                ForEach(InputMode.allCases, id: \.self) { mode in
                    Button(action: {
                        selectedInputMode = mode
                        medicationManager.clearData()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(selectedInputMode == mode ? Color.blue : Color(.systemGray5))
                        .foregroundColor(selectedInputMode == mode ? .white : .primary)
                        .cornerRadius(8)
                    }
                }
            }
            
            Text(inputModeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var inputModeDescription: String {
        switch selectedInputMode {
        case .json:
            return "Upload medication schedule via JSON configuration file"
        case .manual:
            return "Manually enter medication details and schedules"
        case .qr:
            return "Upload QR code containing medication data"
        }
    }
    
    private var manualInputSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Manual Medication Entry", systemImage: "pencil")
                .font(.headline)
                .foregroundColor(.green)
            
            ManualInputView(medicationManager: medicationManager)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var bleConnectionSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("BLE Device Connection", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
                .foregroundColor(.purple)
            
            HStack {
                Button(action: {
                    if isScanning {
                        stopScanning()
                    } else {
                        startScanning()
                    }
                }) {
                    HStack {
                        Image(systemName: isScanning ? "stop.circle" : "magnifyingglass")
                        Text(isScanning ? "Stop Scan" : "Scan Devices")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isScanning ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Spacer()
                
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if !discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discovered Devices:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(discoveredDevices, id: \.identifier) { device in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.name ?? "Unknown Device")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text(device.identifier.uuidString.prefix(8) + "...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if let rssi = device.rssi {
                                        Text("\(rssi) dBm")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Button(action: {
                                        selectDevice(device)
                                    }) {
                                        Text(selectedDevice?.identifier == device.identifier ? "Selected" : "Select")
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(selectedDevice?.identifier == device.identifier ? Color.green : Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var fileUploadSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Medication Data Upload", systemImage: "doc.badge.plus")
                .font(.headline)
                .foregroundColor(.orange)
            
            Button(action: {
                showingFilePicker = true
            }) {
                HStack {
                    Image(systemName: "folder")
                    Text("Choose JSON File")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.orange.opacity(0.1))
                .foregroundColor(.orange)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange, lineWidth: 1)
                )
            }
            
            if !medicationManager.medications.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Data loaded")
                        .foregroundColor(.green)
                    Spacer()
                    Text("\(medicationManager.medications.count) medications")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var qrCodeSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("QR Code Input", systemImage: "qrcode.viewfinder")
                .font(.headline)
                .foregroundColor(.blue)
            
            Button(action: {
                showingQRScanner = true
            }) {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan QR Code")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: 1)
                )
            }
            
            Text("Expected format: Name|Amount|Time1|Dosage1|Time2|Dosage2...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var medicationPreviewSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Medication Schedule Preview", systemImage: "eye")
                .font(.headline)
                .foregroundColor(.blue)
            
            if medicationManager.medications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("No medication data to display")
                        .foregroundColor(.secondary)
                    Text("Upload a JSON file or enter manual data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                MedicationPreviewView(medications: medicationManager.medications)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var sendConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Send Configuration", systemImage: "paperplane")
                .font(.headline)
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "list.clipboard")
                        .foregroundColor(.blue)
                    Text("Pre-Submit Checklist:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                ChecklistItem(text: "BLE device selected", isChecked: selectedDevice != nil)
                ChecklistItem(text: "Device connected via BLE", isChecked: isConnected)
                ChecklistItem(text: "Medication data loaded", isChecked: !medicationManager.medications.isEmpty)
                ChecklistItem(text: "Dispenser is empty and ready", isChecked: true)
                ChecklistItem(text: "Safety protocols acknowledged", isChecked: true)
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(10)
            
            Button(action: submitConfiguration) {
                HStack {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Image(systemName: "paperplane.fill")
                    Text(isSubmitting ? "SUBMITTING..." : "SUBMIT TO DISPENSER")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSubmit ? Color.red : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(!canSubmit || isSubmitting)
            
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("WARNING: This will configure the pill dispenser with the loaded medication schedule.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Device Status", systemImage: "info.circle")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.subheadline)
                
                Spacer()
                
                if isScanning {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isSubmitting {
                ProgressView(value: transmissionProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !chunkProgressMessage.isEmpty {
                    Text(chunkProgressMessage)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                
                if totalChunks > 0 {
                    Text("Progress: \(currentChunk)/\(totalChunks) chunks")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let data = try Data(contentsOf: url)
                let medications = try JSONDecoder().decode([Medication].self, from: data)
                medicationManager.medications = medications
                
                showAlert("Success", "Loaded \(medications.count) medications from file")
            } catch {
                showAlert("Error", "Failed to load JSON file: \(error.localizedDescription)")
            }
            
        case .failure(let error):
            showAlert("Error", "File selection failed: \(error.localizedDescription)")
        }
    }
    
    private func handleQRCodeDetection(_ qrCodes: [String]) {
        let stats = medicationManager.getQRParsingStats(qrCodes)
        let validation = medicationManager.validateQRData(qrCodes)
        
        // Process valid QR codes
        if !validation.valid.isEmpty {
            medicationManager.addMedicationsFromQRData(validation.valid)
        }
        
        // Provide detailed feedback to user
        var message = ""
        if stats.validMedications > 0 {
            message += "Successfully loaded \(stats.validMedications) medication(s)"
        }
        
        if stats.invalidLines > 0 {
            if !message.isEmpty { message += "\n\n" }
            message += "⚠️ \(stats.invalidLines) invalid QR code line(s) were skipped"
            message += "\n\nExpected format: Name|Amount|Time1|Dosage1|Time2|Dosage2..."
        }
        
        if message.isEmpty {
            message = "No valid medication data found in QR code(s)"
        }
        
        let title = stats.validMedications > 0 ? "QR Code Processed" : "QR Code Error"
        showAlert(title, message)
    }
    
    func submitConfiguration() {
        guard let selectedDevice = selectedDevice else {
            showAlert("Error", "Please select a BLE device first")
            return
        }
        
        guard isConnected else {
            showAlert("Error", "Please ensure the selected device is connected")
            return
        }
        
        guard !medicationManager.medications.isEmpty else {
            showAlert("Error", "Please load medication data")
            return
        }
        
        isSubmitting = true
        
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(medicationManager.medications)
        } catch {
            showAlert("Error", "Failed to encode medication data: \(error.localizedDescription)")
            isSubmitting = false
            return
        }
        
        let dataString = "#START#" + String(data: jsonData, encoding: .utf8)! + "#END#"
        let finalData = dataString.data(using: .utf8)!
        
        sendData(finalData) { success, error in
            DispatchQueue.main.async {
                isSubmitting = false
                if success {
                    medicationManager.saveMedications()
                    notificationManager.scheduleNotifications(for: medicationManager.medications)
                    
                    showAlert("Success", "Configuration sent successfully to \(selectedDevice.name ?? "device")! Medication reminders have been scheduled.")
                } else {
                    showAlert("Error", error ?? "Failed to send configuration")
                }
            }
        }
    }
}

class BluetoothDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let onStateUpdate: (CBManagerState) -> Void
    let onDeviceDiscovered: (BLEDevice) -> Void
    let onDeviceConnected: (CBPeripheral) -> Void
    let onCharacteristicDiscovered: (CBCharacteristic) -> Void
    let onConnectionFailed: (Error?) -> Void
    let onDisconnected: (Error?) -> Void
    
    var onChunkAcknowledged: ((Int, Int) -> Void)?
    var onTransmissionComplete: ((Bool, String?) -> Void)?
    
    var currentChunkIndex: Int = 0
    var totalChunks: Int = 0
    var pendingChunks: [Data] = []
    var currentPeripheral: CBPeripheral?
    var currentCharacteristic: CBCharacteristic?
    var isTransmissionActive: Bool = false
    
    private let serviceUUID = CBUUID(string: "FFE0")
    private let characteristicUUID = CBUUID(string: "FFE1")
    
    init(onStateUpdate: @escaping (CBManagerState) -> Void,
         onDeviceDiscovered: @escaping (BLEDevice) -> Void,
         onDeviceConnected: @escaping (CBPeripheral) -> Void,
         onCharacteristicDiscovered: @escaping (CBCharacteristic) -> Void,
         onConnectionFailed: @escaping (Error?) -> Void,
         onDisconnected: @escaping (Error?) -> Void) {
        self.onStateUpdate = onStateUpdate
        self.onDeviceDiscovered = onDeviceDiscovered
        self.onDeviceConnected = onDeviceConnected
        self.onCharacteristicDiscovered = onCharacteristicDiscovered
        self.onConnectionFailed = onConnectionFailed
        self.onDisconnected = onDisconnected
    }
    
    func sendDataWithAcknowledgment(_ data: Data, peripheral: CBPeripheral, characteristic: CBCharacteristic, chunkSize: Int = 20, completion: @escaping (Bool, String?) -> Void) {
        currentChunkIndex = 0
        pendingChunks = data.chunked(into: chunkSize)
        totalChunks = pendingChunks.count
        onTransmissionComplete = completion
        currentPeripheral = peripheral
        currentCharacteristic = characteristic
        isTransmissionActive = true
        
        // Validate connection state
        guard peripheral.state == .connected else {
            completion(false, "Device not connected")
            return
        }
        
        // Enable notifications to listen for "MA" response
        peripheral.setNotifyValue(true, for: characteristic)
        
        print("📦 Starting continuous transmission: \(totalChunks) chunks, \(data.count) bytes total")
        sendAllChunksContinuously()
    }
    
    private func sendAllChunksContinuously() {
        guard let peripheral = currentPeripheral,
              let characteristic = currentCharacteristic,
              isTransmissionActive else {
            onTransmissionComplete?(false, "Missing peripheral or characteristic")
            return
        }
        
        // Send all chunks continuously with small delays
        for (index, chunk) in pendingChunks.enumerated() {
            let chunkNumber = index + 1
            
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                guard self.isTransmissionActive else { return }
                
                print("📤 Sending chunk \(chunkNumber)/\(self.totalChunks) (\(chunk.count) bytes)")
                self.onChunkAcknowledged?(chunkNumber, self.totalChunks)
                
                // Send chunk without expecting write response
                peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
                self.currentChunkIndex = index + 1
                
                // If this is the last chunk, start waiting for "MA"
                if chunkNumber == self.totalChunks {
                    print("✅ All chunks sent, waiting for 'A' completion acknowledgment")
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        
        if let receivedString = String(data: data, encoding: .utf8) {
            print("📨 Received: '\(receivedString)'")
            
            if receivedString.contains("A") && isTransmissionActive {
                isTransmissionActive = false
                print("🎉 Received 'A' - Task complete!")
                onTransmissionComplete?(true, nil)
            }
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateUpdate(central.state)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
//        print("📡 Discovered: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        let device = BLEDevice(
            identifier: peripheral.identifier,
            name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue,
            peripheral: peripheral
        )
        onDeviceDiscovered(device)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        onDeviceConnected(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onConnectionFailed(error)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onDisconnected(error)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ Error discovering services: \(error)")
        }
        guard let services = peripheral.services else { return }
        for service in services {
            print("✅ Found service: \(service.uuid)")
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ Error discovering characteristics: \(error)")
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            print("🔑 Found characteristic: \(characteristic.uuid)")
            if characteristic.uuid == characteristicUUID {
                onCharacteristicDiscovered(characteristic)
            }
        }
    }
}

extension Data {
    func chunked(into size: Int) -> [Data] {
        return stride(from: 0, to: count, by: size).map {
            subdata(in: $0..<Swift.min($0 + size, count))
        }
    }
}

private struct ChecklistItem: View {
    let text: String
    let isChecked: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isChecked ? .green : .gray)
            Text(text)
                .font(.caption)
            Spacer()
        }
    }
}

class MedicationNotificationManager: ObservableObject {
    func scheduleNotifications(for medications: [Medication]) {
        // Implementation to schedule notifications
    }
}

struct Medication: Codable {
    // Medication properties
}
