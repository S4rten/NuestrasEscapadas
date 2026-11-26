import SwiftUI

// ============================================================================
// RECUERDOS: escapadas ya vividas, con podio, orden y filtro por nota.
// ============================================================================

private enum OrdenRecuerdos: String, CaseIterable, Identifiable {
    case recientes = "Recientes"
    case mejorNota = "Mejor nota"

    var id: String { rawValue }
}

private enum NotaMinima: Double, CaseIterable, Identifiable {
    case todas = 0
    case tres = 3
    case cuatro = 4
    case cuatroMedia = 4.5

    var id: Double { rawValue }

    var etiqueta: String {
        switch self {
        case .todas: return "Todas"
        case .tres: return "3★ o más"
        case .cuatro: return "4★ o más"
        case .cuatroMedia: return "4,5★ o más"
        }
    }
}

struct YaVividoView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    @State private var orden: OrdenRecuerdos = .recientes
    @State private var minima: NotaMinima = .todas

    private var vividas: [Escapada] {
        almacen.escapadas.filter { $0.yaVivida && !$0.sorpresaOculta(para: sesion.miId) }
    }

    private var podio: [Escapada] {
        Array(
            vividas
                .filter { $0.valoracion.media != nil }
                .sorted { ($0.valoracion.media ?? 0) > ($1.valoracion.media ?? 0) }
                .prefix(3)
        )
    }

    private var lista: [Escapada] {
        var resultado = vividas
        if minima != .todas {
            resultado = resultado.filter { ($0.valoracion.media ?? 0) >= minima.rawValue }
        }
        switch orden {
        case .recientes:
            resultado.sort { $0.fechaInicio > $1.fechaInicio }
        case .mejorNota:
            resultado.sort { ($0.valoracion.media ?? 0) > ($1.valoracion.media ?? 0) }
        }
        return resultado
    }

    var body: some View {
        List {
            if vividas.isEmpty {
                ContentUnavailableView(
                    "Aún no hay recuerdos",
                    systemImage: "heart.slash",
                    description: Text("Cuando termine una escapada, la podréis puntuar y guardar aquí.")
                )
            } else {
                Section {
                    NavigationLink {
                        EstadisticasView()
                    } label: {
                        Label("Estadísticas y países visitados", systemImage: "chart.bar.fill")
                    }
                    NavigationLink {
                        FavoritosView()
                    } label: {
                        Label("Vuestros sitios favoritos", systemImage: "star.fill")
                    }
                }

                if !podio.isEmpty {
                    Section("🏆 Vuestro podio") {
                        ForEach(Array(podio.enumerated()), id: \.element.id) { indice, e in
                            NavigationLink(value: e.id) {
                                HStack(spacing: 12) {
                                    Text(["🥇", "🥈", "🥉"][indice])
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.titulo)
                                            .font(.subheadline.weight(.semibold))
                                        Text(e.destino)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let media = e.valoracion.media {
                                        InsigniaMedia(media: media)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("Orden", selection: $orden) {
                        ForEach(OrdenRecuerdos.allCases) { o in
                            Text(o.rawValue).tag(o)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Nota mínima", selection: $minima) {
                        ForEach(NotaMinima.allCases) { n in
                            Text(n.etiqueta).tag(n)
                        }
                    }
                }

                Section("Todas las escapadas") {
                    if lista.isEmpty {
                        Text("Ninguna escapada cumple ese filtro.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lista) { e in
                        NavigationLink(value: e.id) {
                            filaRecuerdo(e)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: String.self) { id in
            DetalleEscapadaView(escapadaId: id)
        }
    }

    private func filaRecuerdo(_ e: Escapada) -> some View {
        HStack(spacing: 12) {
            Text(e.icono)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(e.titulo)
                    .font(.subheadline.weight(.semibold))
                Text("\(e.destino) · \(e.fechaInicio.formatted(.dateTime.month(.abbreviated).year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                let gasto = almacen.totalGastado(e.id)
                if gasto > 0 {
                    Text("💶 \(gasto.formatoDivisa())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let media = e.valoracion.media {
                InsigniaMedia(media: media)
            } else {
                Text("Sin nota")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
