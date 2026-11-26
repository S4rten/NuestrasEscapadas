import SwiftUI
import MapKit

// ============================================================================
// MAPA: chinchetas de todas las escapadas con coordenadas.
// Las sorpresas aún ocultas para ti no aparecen ni en el mapa ni en la lista.
// ============================================================================

struct MapaView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    @State private var camara: MapCameraPosition = .automatic

    private var visibles: [Escapada] {
        almacen.escapadas
            .filter { !$0.sorpresaOculta(para: sesion.miId) }
            .sorted { $0.fechaInicio > $1.fechaInicio }
    }

    private var conCoordenadas: [Escapada] {
        visibles.filter { $0.latitud != nil && $0.longitud != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camara) {
                ForEach(conCoordenadas) { e in
                    Marker(
                        "\(e.icono) \(e.titulo)",
                        coordinate: CLLocationCoordinate2D(
                            latitude: e.latitud ?? 0,
                            longitude: e.longitud ?? 0
                        )
                    )
                }
            }
            .frame(height: 300)

            List {
                if visibles.isEmpty {
                    ContentUnavailableView(
                        "Todavía no hay escapadas",
                        systemImage: "map",
                        description: Text("Cuando añadáis viajes, aparecerán aquí.")
                    )
                } else {
                    Section {
                        ForEach(visibles) { e in
                            NavigationLink(value: e.id) {
                                HStack(spacing: 12) {
                                    Text(e.icono)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.titulo)
                                            .font(.subheadline.weight(.semibold))
                                        Text(e.destino)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if e.latitud == nil || e.longitud == nil {
                                        Image(systemName: "mappin.slash")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } footer: {
                        if conCoordenadas.count < visibles.count {
                            Text("Las escapadas con el icono tachado no tienen ubicación exacta: edítalas y elige el destino de la lista de sugerencias.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationDestination(for: String.self) { id in
            DetalleEscapadaView(escapadaId: id)
        }
    }
}
