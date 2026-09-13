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
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(AppTheme.primary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
