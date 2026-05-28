//
//  ToolbarFeatureIcon.swift
//  Liney
//
//  Author: everettjf
//

import SwiftUI

struct ToolbarFeatureIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 16, height: 16)

            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}
