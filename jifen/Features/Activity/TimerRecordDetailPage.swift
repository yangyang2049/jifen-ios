import SwiftUI

struct TimerRecordDetailPage: View {
    let recordId: String // Or String, depending on how activity.id is defined

    var body: some View {
        Text("Timer Record Detail Page (Placeholder) for ID: \(recordId)")
            .navigationTitle("Timer Record Detail")
    }
}

#Preview {
    TimerRecordDetailPage(recordId: "dummy-id")
}