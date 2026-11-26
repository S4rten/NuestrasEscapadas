import SwiftUI
import UIKit

// ============================================================================
// PIEZAS DE INTERFAZ REUTILIZABLES
// ============================================================================

struct Chip: View {
    let texto: String
    var color: Color = .accentColor

    var body: some View {
        Text(texto)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct InsigniaMedia: View {
    let media: Double
    var grande: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.caption2)
            Text(String(format: "%.1f", media))
                .font((grande ? Font.subheadline : Font.caption).bold().monospacedDigit())
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.14))
        .clipShape(Capsule())
    }
}

struct BannerError: View {
    let mensaje: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(mensaje)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Botón que copia un texto al portapapeles y muestra un ✓ durante dos segundos.
struct BotonCopiar: View {
    let etiqueta: String
    let valor: String
    @State private var copiado = false

    var body: some View {
        Button {
            UIPasteboard.general.string = valor
            copiado = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiado = false }
        } label: {
            HStack(spacing: 4) {
                Text("\(etiqueta): \(valor)")
                    .font(.caption.monospaced().bold())
                Image(systemName: copiado ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
            }
        }
        .buttonStyle(.bordered)
    }
}

/// Botón que abre un enlace. Se usa en vez de `Link` dentro de filas de lista,
/// para que varios botones en la misma fila no se disparen a la vez.
struct BotonEnlace: View {
    let titulo: String
    let url: URL
    var icono: String = "safari"
    @Environment(\.openURL) private var abrirURL

    var body: some View {
        Button {
            abrirURL(url)
        } label: {
            Label(titulo, systemImage: icono)
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct FilaEstrellas: View {
    let titulo: String
    let puntuacion: Int
    let alCambiar: (Int) -> Void

    var body: some View {
        HStack {
            Text(titulo)
                .font(.caption.weight(.medium))
            Spacer()
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { estrella in
                    Button {
                        alCambiar(puntuacion == estrella ? 0 : estrella)
                    } label: {
                        Image(systemName: estrella <= puntuacion ? "star.fill" : "star")
                            .font(.subheadline)
                            .foregroundStyle(estrella <= puntuacion ? Color.orange : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Editor de texto largo que guarda SOLO al salir del campo (no en cada letra),
/// y no pisa lo que estás escribiendo si tu pareja cambia el texto a la vez.
struct EditorTextoGuardable: View {
    let titulo: String
    let valorRemoto: String
    let placeholder: String
    let alGuardar: (String) -> Void

    @State private var texto = ""
    @FocusState private var enfocado: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if texto.isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $texto)
                    .focused($enfocado)
                    .frame(minHeight: 110)
            }
        }
        .onAppear { texto = valorRemoto }
        .onChange(of: valorRemoto) { _, nuevo in
            if !enfocado { texto = nuevo }
        }
        .onChange(of: enfocado) { _, ahora in
            if !ahora && texto != valorRemoto { alGuardar(texto) }
        }
        .onDisappear {
            if texto != valorRemoto { alGuardar(texto) }
        }
    }
}
