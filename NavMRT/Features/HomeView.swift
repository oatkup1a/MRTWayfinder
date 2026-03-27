import SwiftUI

struct HomeView: View {
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    modeCard

                    VStack(spacing: 16) {
                        NavigationLink {
                            AutoDetectRouteView()
                        } label: {
                            HomeActionCard(
                                title: "Auto Detect Current Station",
                                subtitle: "Scan nearby beacons, confirm where the rider is, then choose a destination.",
                                systemImage: "dot.radiowaves.left.and.right",
                                accent: Color(red: 0.06, green: 0.45, blue: 0.40)
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            RouteSelectionView()
                        } label: {
                            HomeActionCard(
                                title: "Choose Start and Destination",
                                subtitle: "Manually select the start station and destination before starting guidance.",
                                systemImage: "map.fill",
                                accent: Color(red: 0.77, green: 0.30, blue: 0.15)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }

            NavigationLink {
                DeveloperToolsView()
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    .accessibilityLabel("Developer tools")
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .background(Color(red: 0.93, green: 0.91, blue: 0.86))
        .navigationTitle("NavMRT")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Indoor guidance, with a faster start.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.12, green: 0.11, blue: 0.10))

            Text("Start from a detected station or choose your route manually. Developer tools stay tucked away in the corner.")
                .font(.body)
                .foregroundStyle(Color(red: 0.29, green: 0.25, blue: 0.18))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.88, blue: 0.69),
                    Color(red: 0.95, green: 0.97, blue: 0.86),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: useMockBeacons ? "waveform.path.ecg" : "dot.radiowaves.up.forward")
                    .font(.title3)
                    .foregroundStyle(useMockBeacons ? .orange : .green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(useMockBeacons ? "Mock beacon mode is active" : "Real beacon mode is active")
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
                    Text("Choose the beacon source before starting guidance.")
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.30, green: 0.28, blue: 0.24))
                }

                Spacer()
            }

            HStack(spacing: 10) {
                modeButton(
                    title: "Real",
                    systemImage: "dot.radiowaves.up.forward",
                    isSelected: !useMockBeacons,
                    activeColor: Color(red: 0.16, green: 0.56, blue: 0.28)
                ) {
                    useMockBeacons = false
                }

                modeButton(
                    title: "Mock",
                    systemImage: "waveform.path.ecg",
                    isSelected: useMockBeacons,
                    activeColor: Color(red: 0.86, green: 0.52, blue: 0.10)
                ) {
                    useMockBeacons = true
                }
            }
        }
        .padding(18)
        .background(Color(red: 0.99, green: 0.98, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private func modeButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? .white : activeColor)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? activeColor : activeColor.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(activeColor.opacity(isSelected ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 48, height: 48)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.13, green: 0.12, blue: 0.11))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.30, green: 0.28, blue: 0.24))
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 0.30, green: 0.28, blue: 0.24))
        }
        .padding(18)
        .background(Color(red: 0.99, green: 0.98, blue: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}
