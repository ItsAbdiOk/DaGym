import SwiftUI

/// One onboarding screen's shape (the prototype's `sOb`): a centred accent glyph, kicker,
/// title and one-line body, the step's own content (usually an `OnboardingOptionGroup`), then
/// the page dots and a full-width call to action pinned to the bottom. The title carries
/// `A11yID.onboardingStep(name)`, which the walkthrough UI test waits on per step.
struct OnboardingPage<Content: View>: View {
    var step: OnboardingStep
    var name: String
    var symbol: String
    var title: String
    var message: String
    var cta: String
    var ctaDisabled = false
    var onContinue: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    glyph
                    Text(step.kicker)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DGColor.ink3)
                        .padding(.top, 22)
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(DGColor.ink1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 310)
                        .padding(.top, 10)
                        .accessibilityIdentifier(A11yID.onboardingStep(name))
                    Text(message)
                        .font(DGFont.subhead)
                        .foregroundStyle(DGColor.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 296)
                        .padding(.top, 12)
                    content
                        .padding(.top, 30)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DGSpace.s6)
                .padding(.top, 28)
                .padding(.bottom, DGSpace.s4)
            }
            footer
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(DGColor.coral)
            .frame(width: 76, height: 76)
            .background(DGColor.coralWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                    Circle()
                        .fill(candidate == step ? DGColor.coral : DGColor.ink1.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.kicker)
            DGPrimaryButton(title: cta, height: 50, action: onContinue)
                .accessibilityIdentifier(A11yID.onboardingNext)
                .disabled(ctaDisabled)
                .opacity(ctaDisabled ? 0.4 : 1)
        }
        .padding(.horizontal, DGSpace.s5)
        .padding(.top, 14)
        .padding(.bottom, DGSpace.s3)
    }
}

/// The white group of rows under a step's title: options to pick from, or plain info rows.
struct OnboardingOptionGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DGColor.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color(hex: 0x3C2814).opacity(0.09), radius: 2, y: 1)
    }
}

/// One selectable row: title, optional sub line, an accent tick and wash when selected.
/// The accessibility label is the title alone (the sub is the hint), so a test can find
/// "Pounds" or "Home" by exact label.
struct OnboardingOptionRow: View {
    var title: String
    var sub: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DGSpace.s3) {
                OnboardingRowText(title: title, sub: sub)
                Spacer(minLength: DGSpace.s2)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DGColor.coral)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DGSpace.s4)
            .padding(.vertical, 13)
            .frame(minHeight: 56)
            .background(isSelected ? DGColor.coralWash : .clear)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DGColor.hairline).frame(height: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.dgRow)
        .accessibilityLabel(title)
        .accessibilityHint(sub ?? "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A row that only informs (what a permission step will do), no selection.
struct OnboardingInfoRow: View {
    var symbol: String
    var title: String
    var sub: String?

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DGColor.coral)
                .frame(width: 24)
                .accessibilityHidden(true)
            OnboardingRowText(title: title, sub: sub)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DGSpace.s4)
        .padding(.vertical, 13)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DGColor.hairline).frame(height: 0.5)
        }
    }
}

/// A read-only "label … value" row, for the final summary.
struct OnboardingSummaryRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: DGSpace.s3) {
            Text(label).font(DGFont.body).foregroundStyle(DGColor.ink1)
            Spacer()
            Text(value).font(DGFont.body).foregroundStyle(DGColor.ink3)
        }
        .padding(.horizontal, DGSpace.s4)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DGColor.hairline).frame(height: 0.5)
        }
    }
}

private struct OnboardingRowText: View {
    var title: String
    var sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(DGFont.body).foregroundStyle(DGColor.ink1)
            if let sub {
                Text(sub)
                    .font(DGFont.footnote)
                    .foregroundStyle(DGColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.leading)
    }
}
