import SwiftUI

// ============================================================================
// VALORAR AL VOLVER: estrellas y "repetiríamos" para cada plan y alojamiento.
// Con eso salen vuestros sitios favoritos y una guía para pasar a amigos
// (solo sitios y notas: nada de gastos ni datos privados).
// ============================================================================

/// Sección de la pestaña Recuerdo: puntuar cada plan y alojamiento del viaje.
struct SeccionValorarPlanes: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada

    var body: some View {
        let planes = almacen.actividadesDe(escapada.id).sorted { a, b in
            a.dia != b.dia ? a.dia < b.dia : (a.hora ?? a.creadaEn) < (b.hora ?? b.creadaEn)
        }
        let alojamientos = almacen.alojamientosDe(escapada.id)
        let valorados = planes.filter { $0.estrellas > 0 }.count + alojamientos.filter { $0.estrellas > 0 }.count
        let total = planes.count + alojamientos.count

        if total > 0 {
            Section {
                ForEach(alojamientos) { h in
                    FilaEstrellas(titulo: "🛏️ \(h.nombre.isEmpty ? "Alojamiento" : h.nombre)", puntuacion: h.estrellas) {
                        almacen.actualizar(h.id, en: .alojamientos, campos: ["estrellas": $0])
                    }
                }
                ForEach(planes) { a in
                    HStack(spacing: 8) {
                        Button {
                            almacen.actualizar(a.id, en: .actividades, campos: ["repetiriamos": !a.repetiriamos])
                        } label: {
                            Image(systemName: a.repetiriamos ? "heart.fill" : "heart")
                                .foregroundStyle(a.repetiriamos ? Color.pink : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(a.repetiriamos ? "Repetiríamos" : "Marcar que repetiríamos")

                        FilaEstrellas(titulo: "\(a.nombreSitio) · día \(a.dia)", puntuacion: a.estrellas) {
                            almacen.actualizar(a.id, en: .actividades, campos: ["estrellas": $0])
                        }
                    }
                }
            } header: {
                Text("Valorar planes y sitios · \(valorados)/\(total)")
            } footer: {
                Text("❤️ = repetiríamos. Con las estrellas se forma vuestra lista de favoritos (en Recuerdos) y la guía para amigos.")
            }

            if valorados > 0 {
                SeccionGuiaAmigos(escapada: escapada)
            }
        }
    }
}

/// Texto para compartir con amigos con los sitios recomendados del viaje.
struct SeccionGuiaAmigos: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada

    var body: some View {
        let texto = GuiaViaje.texto(escapada: escapada, almacen: almacen)
        Section {
            ShareLink(item: texto) {
                Label("Compartir guía con amigos", systemImage: "square.and.arrow.up")
            }
            DisclosureGroup("Ver cómo queda") {
                Text(texto)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } footer: {
            Text("Solo incluye los sitios y vuestras estrellas: ni gastos, ni reservas, ni el diario.")
        }
    }
}

enum GuiaViaje {
    private static func estrellas(_ n: Int) -> String {
        String(repeating: "★", count: n) + String(repeating: "☆", count: max(0, 5 - n))
    }

    @MainActor
    static func texto(escapada e: Escapada, almacen: Almacen) -> String {
        let planes = almacen.actividadesDe(e.id).filter { $0.estrellas > 0 }
        let alojamientos = almacen.alojamientosDe(e.id).filter { $0.estrellas > 0 }
        var lineas: [String] = []

        lineas.append("\(e.icono) \(e.destino.isEmpty ? e.titulo : e.destino) · \(e.fechaInicio.formatted(.dateTime.month(.wide).year()))")
        if let media = e.valoracion.media {
            lineas.append("Nuestra nota del viaje: \(String(format: "%.1f", media).replacingOccurrences(of: ".", with: ",")) / 5")
        }

        let imprescindibles = planes.filter { $0.estrellas >= 4 }.sorted { $0.estrellas > $1.estrellas }
        if !imprescindibles.isEmpty {
            lineas.append("")
            lineas.append("⭐️ IMPRESCINDIBLES")
            for a in imprescindibles {
                lineas.append("• \(a.nombreSitio) \(estrellas(a.estrellas))\(a.repetiriamos ? " ❤️ repetiríamos" : "")")
            }
        }

        let bien = planes.filter { $0.estrellas == 3 }
        if !bien.isEmpty {
            lineas.append("")
            lineas.append("👍 SI TENÉIS TIEMPO")
            for a in bien { lineas.append("• \(a.nombreSitio)") }
        }

        let flojos = planes.filter { $0.estrellas <= 2 }
        if !flojos.isEmpty {
            lineas.append("")
            lineas.append("🤷 NOS LO SALTARÍAMOS")
            for a in flojos { lineas.append("• \(a.nombreSitio)") }
        }

        if !alojamientos.isEmpty {
            lineas.append("")
            lineas.append("🛏️ DÓNDE DORMIMOS")
            for h in alojamientos {
                lineas.append("• \(h.nombre.isEmpty ? "Alojamiento" : h.nombre) \(estrellas(h.estrellas))")
            }
        }

        lineas.append("")
        lineas.append("— Hecha con Nuestras Escapadas ✈️")
        return lineas.joined(separator: "\n")
    }
}

// ============================================================================
// FAVORITOS: lo mejor de todos los viajes (4★ o más, o "repetiríamos").
// ============================================================================

struct FavoritosView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @State private var soloRepetir = false

    var body: some View {
        let viajes = almacen.escapadas
            .filter { $0.yaVivida && !$0.sorpresaOculta(para: sesion.miId) }
            .sorted { $0.fechaInicio > $1.fechaInicio }

        List {
            Section {
                Toggle("Solo los que repetiríamos ❤️", isOn: $soloRepetir)
            }

            let conFavoritos = viajes.filter { !favoritos(de: $0).isEmpty }
            if conFavoritos.isEmpty {
                ContentUnavailableView(
                    "Aún no hay favoritos",
                    systemImage: "star",
                    description: Text("Al volver de un viaje, puntuad los planes en su pestaña Recuerdo. Los de 4★ o más (o con ❤️) aparecen aquí.")
                )
            }

            ForEach(conFavoritos) { e in
                Section {
                    ForEach(favoritos(de: e)) { a in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.nombreSitio)
                                    .font(.subheadline.weight(.medium))
                                if a.repetiriamos {
                                    Text("❤️ Repetiríamos")
                                        .font(.caption2)
                                        .foregroundStyle(.pink)
                                }
                            }
                            Spacer()
                            if a.estrellas > 0 {
                                Text(String(repeating: "★", count: a.estrellas))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    Text("\(e.icono) \(e.titulo) · \(e.fechaInicio.formatted(.dateTime.month(.abbreviated).year()))")
                }
            }
        }
        .navigationTitle("Vuestros favoritos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func favoritos(de e: Escapada) -> [Actividad] {
        almacen.actividadesDe(e.id)
            .filter { soloRepetir ? $0.repetiriamos : ($0.estrellas >= 4 || $0.repetiriamos) }
            .sorted { $0.estrellas > $1.estrellas }
    }
}
