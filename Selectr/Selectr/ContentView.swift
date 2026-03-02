import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "star.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Welcome to Selectr")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
