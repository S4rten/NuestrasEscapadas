import SwiftUI
import Network

// ============================================================================
// SIN CONEXIÓN: Firestore guarda una copia de todo en el iPhone, así que la app
// funciona en el avión. Aquí se vigila la red para avisar con claridad de que
// los cambios se guardan en el iPhone y se sincronizan solos al volver.
// ============================================================================

@MainActor
final class MonitorConexion: ObservableObject {
    static let compartido = MonitorConexion()

    @Published private(set) var hayConexion = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] ruta in
            let conectado = ruta.status == .satisfied
            Task { @MainActor in
                self?.hayConexion = conectado
            }
        }
        monitor.start(queue: DispatchQueue(label: "nuestrasescapadas.monitor-conexion"))
    }
}

struct BannerSinConexion: View {
    @EnvironmentObject var almacen: Almacen
    @ObservedObject private var red = MonitorConexion.compartido

    var body: some View {
        if !red.hayConexion {
            aviso(
                icono: "wifi.slash",
                titulo: "Sin conexión",
                texto: "Podéis seguir usando la app con normalidad: los cambios se guardan en este iPhone y se sincronizan solos al volver la conexión.",
                color: .orange
            )
        } else if almacen.subidaRetrasada {
            aviso(
                icono: "arrow.triangle.2.circlepath",
                titulo: "Sincronizando…",
                texto: "Subiendo a la nube los cambios hechos sin conexión.",
                color: .blue
            )
        }
    }

    private func aviso(icono: String, titulo: String, texto: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icono)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.caption.bold())
                Text(texto)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
