import SwiftUI
import Vision
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import PhotosUI

class BackgroundRemovalManager: ObservableObject {
    @Published var isLoading = false
    @Published var inputImage: NSImage?
    @Published var processedImage: NSImage?
    @Published var uploadState: UploadState = .idle
    
    private let processingQueue = DispatchQueue(label: "ProcessingImageQueue")
    private let lock = NSLock()
    
    enum UploadState {
        case idle
        case uploading
        case processing
        case completed
        case error(String)
    }
    
    func processImage(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            uploadState = .error("Failed to process image")
            return
        }
        
        Task { @MainActor in
            isLoading = true
            uploadState = .processing
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let imageSize = image.size
        
        Task.detached(priority: .userInitiated) {
            if let maskImage = await self.createMaskImage(from: ciImage),
               let outputImage = self.apply(mask: maskImage, to: ciImage),
               let cgOutput = CIContext().createCGImage(outputImage, from: outputImage.extent) {
                await MainActor.run {
                    self.processedImage = NSImage(cgImage: cgOutput, size: imageSize)
                    self.isLoading = false
                    self.uploadState = .completed
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.uploadState = .error("Failed to process image")
                }
            }
        }
    }
    
    private func createMaskImage(from inputImage: CIImage) async -> CIImage? {
        let handler = VNImageRequestHandler(ciImage: inputImage)
        let request = VNGenerateForegroundInstanceMaskRequest()
        
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }
            let maskPixel = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
            return CIImage(cvPixelBuffer: maskPixel)
        } catch {
            print("Error creating mask: \(error)")
            return nil
        }
    }
    
    private func apply(mask: CIImage, to image: CIImage) -> CIImage? {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.maskImage = mask
        filter.backgroundImage = CIImage.empty()
        return filter.outputImage
    }
}

struct ContentView: View {
    @StateObject private var manager = BackgroundRemovalManager()
    @State private var showingPhotoPicker = false
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ZStack {
                    if let image = manager.processedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 400, maxHeight: 400)
                            .transition(.opacity)
                            .contextMenu {
                                Button("Copy Image") {
                                    copyImageToPasteboard(image)
                                }
                                Button("Save Image") {
                                    saveProcessedImage()
                                }
                            }
                    } else if let image = manager.inputImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 400, maxHeight: 400)
                            .transition(.opacity)
                    } else {
                        DropZoneView(isDragging: $isDragging, showingPhotoPicker: $showingPhotoPicker)
                    }
                    
                    if manager.isLoading {
                        LoaderView()
                    }
                    
                    if case .error(let message) = manager.uploadState {
                        Text(message)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                    }
                }
                .animation(.easeInOut, value: manager.processedImage != nil)
                
                if manager.processedImage != nil {
                    HStack(spacing: 20) {
                        Button("Copy") {
                            if let image = manager.processedImage {
                                copyImageToPasteboard(image)
                            }
                        }
                        .buttonStyle(GlassButtonStyle())
                        
                        Button("Save") {
                            saveProcessedImage()
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                    .disabled(manager.isLoading)
                }
            }
            .padding(30)
        }
        .frame(minWidth: 600, minHeight: 700)
        .fileImporter(
            isPresented: $showingPhotoPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first,
                   let image = NSImage(contentsOf: url) {
                    manager.inputImage = image
                    manager.processImage(image)
                }
            case .failure(let error):
                manager.uploadState = .error(error.localizedDescription)
            }
        }
        .onDrop(of: [.image], isTargeted: $isDragging) { providers in
            guard let provider = providers.first else { return false }
            
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (data, error) in
                if let imageData = data as? Data,
                   let image = NSImage(data: imageData) {
                    Task { @MainActor in
                        manager.inputImage = image
                        manager.processImage(image)
                    }
                } else if let error = error {
                    Task { @MainActor in
                        manager.uploadState = .error(error.localizedDescription)
                    }
                }
            }
            return true
        }
    }
    
    private func copyImageToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    private func saveProcessedImage() {
        guard let processedImage = manager.processedImage else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Processed Image"
        savePanel.message = "Choose a location to save the processed image"
        savePanel.nameFieldStringValue = "processed_image.png"
        
        let response = savePanel.runModal()
        
        if response == .OK,
           let url = savePanel.url,
           let tiffData = processedImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            do {
                try pngData.write(to: url)
            } catch {
                manager.uploadState = .error("Failed to save image: \(error.localizedDescription)")
            }
        }
    }
}
