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
                Image(child.resolvedDefaultAvatar.assetName)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.9), lineWidth: max(size * 0.025, 1))
        }
        .shadow(color: child.color.color.opacity(0.16), radius: max(size * 0.08, 2), y: 2)
        .accessibilityHidden(true)
    }
}

struct ParentAvatarView: View {
    let parent: ParentProfile
    var size: CGFloat = 44

    var body: some View {
        Image(parent.resolvedDefaultAvatar.assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: max(size * 0.025, 1)) }
            .shadow(color: AppTheme.primary.opacity(0.16), radius: max(size * 0.08, 2), y: 2)
            .accessibilityHidden(true)
    }
}

struct DefaultAvatarPicker: View {
    let avatars: [DefaultProfileAvatar]
    @Binding var selection: DefaultProfileAvatar

    private let columns = [GridItem(.adaptive(minimum: 52, maximum: 62), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(avatars) { avatar in
                Button {
                    selection = avatar
                } label: {
                    Image(avatar.assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(selection == avatar ? AppTheme.primary : Color.white, lineWidth: selection == avatar ? 3 : 1.5)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if selection == avatar {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white, AppTheme.primary)
                                    .background(.white, in: Circle())
                            }
                        }
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(avatar.accessibilityName)
                .accessibilityAddTraits(selection == avatar ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
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
