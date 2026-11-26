import SwiftUI
import FirebaseCore

@main
struct NuestrasEscapadasApp: App {
    @StateObject private var sesion = Sesion()
    @StateObject private var almacen = Almacen()
    @StateObject private var divisas = ServicioDivisas()
    private let firebaseListo: Bool

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            firebaseListo = true
        } else {
            firebaseListo = false
        }
    }

    var body: some Scene {
        WindowGroup {
            RaizView(firebaseListo: firebaseListo)
                .environmentObject(sesion)
                .environmentObject(almacen)
                .environmentObject(divisas)
        }
    }
}

/// Decide qué pantalla se ve: error de configuración, bienvenida o la app.
struct RaizView: View {
    @EnvironmentObject var sesion: Sesion
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var divisas: ServicioDivisas
    let firebaseListo: Bool

    var body: some View {
        Group {
            if !firebaseListo {
                ErrorConfiguracionView()
            } else if !sesion.estaConfigurada {
                BienvenidaView()
            } else {
                InicioView()
                    .task(id: sesion.codigo) {
                        await almacen.conectar(codigo: sesion.codigo, miId: sesion.miId, miNombre: sesion.miNombre)
                    }
                    .task {
                        await divisas.actualizarSiHaceFalta()
                    }
            }
        }
    }
}

struct ErrorConfiguracionView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Falta la configuración de Firebase", systemImage: "exclamationmark.triangle.fill")
        } description: {
            Text("No se encuentra GoogleService-Info.plist dentro de la app. Súbelo a la raíz del repositorio de GitHub y vuelve a compilar.")
        }
        .padding()
    }
}
