import SwiftUI
import Vision
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import PhotosUI

class BackgroundRemovalManager: ObservableObject {
    @Published var isLoading = false
    @Published var inputImage: NSImage?
    @Published var processedImage: NSImage?
    private let processingQueue = DispatchQueue(label: "ProcessingImageQueue")
    private let lock = NSLock()
    
    func processImage(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }
        
        Task { @MainActor in
            isLoading = true
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
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
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
            // Glass background
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Image display area
                ZStack {
                    if let image = manager.processedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 400, maxHeight: 400)
                            .transition(.opacity)
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
                }
                .animation(.easeInOut, value: manager.processedImage != nil)
                
                // Save button
                if manager.processedImage != nil {
                    Button("Save Image") {
                        saveProcessedImage()
                    }
                    .buttonStyle(GlassButtonStyle())
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
                print("Error selecting image: \(error)")
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
                }
            }
            return true
        }
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
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url,
               let tiffData = processedImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: url)
            }
        }
    }
}
