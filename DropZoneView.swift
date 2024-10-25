import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    @Binding var showingPhotoPicker: Bool
    
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text("Drop image here or")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Button("Choose File") {
                showingPhotoPicker = true
            }
            .buttonStyle(GlassButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(isDragging ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [10]))
                .background(Color.clear)
        )
        .padding()
    }
}
