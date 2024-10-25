import SwiftUI

struct DropZoneView: View {
    @Binding var isDragging: Bool
    @Binding var showingPhotoPicker: Bool
    
    var body: some View {
        Button(action: {
            showingPhotoPicker = true
        }) {
            VStack(spacing: 15) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                
                Text("Click or drop image here")
                    .font(.title3)
                    .foregroundColor(.secondary)
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
        .buttonStyle(PlainButtonStyle())
    }
}
