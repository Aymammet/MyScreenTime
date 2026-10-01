import SwiftUI

struct ChildAvatarView: View {
    let child: ChildProfile
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let data = child.profilePhotoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(child.color.color.opacity(0.18))
                    Text(child.initials)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(child.color.color)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 12) {
        ChildAvatarView(child: ChildProfile(name: "Alex", colorRawValue: ChildColor.teal.rawValue))
        ChildAvatarView(child: ChildProfile(name: "Sam", colorRawValue: ChildColor.orange.rawValue))
        ChildAvatarView(child: ChildProfile(name: "Maya", colorRawValue: ChildColor.pink.rawValue))
    }
    .padding()
}
