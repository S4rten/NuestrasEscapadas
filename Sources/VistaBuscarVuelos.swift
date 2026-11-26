import SwiftUI
import UIKit
import WebKit

// ============================================================================
// BUSCAR EL VUELO CON LOCALIZADOR Y APELLIDO
// La app abre la web de "Mi reserva" de la aerolínea aquí dentro. El localizador
// y el apellido los escribes tú en su web (la app solo copia el localizador).
// Cuando se ven los vuelos, la app lee de la página los números de vuelo y con
// ellos busca la ruta y los horarios. Lo leído no se guarda ni se envía.
// ============================================================================

struct NavegadorReserva: View {
    let url: URL
    let nombreAerolinea: String
    let localizador: String
    let alEncontrar: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var control = ControlNavegador()
    @State private var mensaje = ""
    @State private var leyendo = false

    var body: some View {
        NavigationStack {
            VistaWeb(url: url, control: control)
                .safeAreaInset(edge: .bottom) {
                    barraInferior
                }
                .navigationTitle(nombreAerolinea)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if control.cargando {
                            ProgressView()
                        } else {
                            Button {
                                control.web?.reload()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
        }
        .onAppear {
            let loc = localizador.recortado
            if loc.isEmpty {
                mensaje = "Escribe en la web el localizador y tu apellido para ver la reserva."
            } else {
                UIPasteboard.general.string = loc
                mensaje = "Localizador \(loc) copiado: pégalo en la web junto a tu apellido."
            }
        }
    }

    private var barraInferior: some View {
        VStack(spacing: 8) {
            Text(mensaje)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                leer()
            } label: {
                Label(leyendo ? "Leyendo…" : "Ya veo mis vuelos: leerlos", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(leyendo)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func leer() {
        guard let web = control.web else { return }
        leyendo = true
        web.evaluateJavaScript(LectorReserva.guion) { resultado, _ in
            let texto = (resultado as? String) ?? ""
            Task { @MainActor in
                leyendo = false
                procesar(texto)
            }
        }
    }

    private func procesar(_ texto: String) {
        let vuelos = LectorReserva.numerosDeVuelo(en: texto)
        if vuelos.isEmpty {
            mensaje = "No veo números de vuelo en esta página. Abre la reserva (donde salen los vuelos) y vuelve a pulsar."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            alEncontrar(vuelos)
            dismiss()
        }
    }
}

@MainActor
final class ControlNavegador: ObservableObject {
    weak var web: WKWebView?
    @Published var cargando = false
}

struct VistaWeb: UIViewRepresentable {
    let url: URL
    let control: ControlNavegador

    func makeCoordinator() -> Coordinador {
        Coordinador(control: control)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuracion = WKWebViewConfiguration()
        // Sin guardar cookies ni sesiones: al cerrar no queda nada de esa web en el iPhone.
        configuracion.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuracion)
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        control.web = web
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinador: NSObject, WKNavigationDelegate, WKUIDelegate {
        let control: ControlNavegador

        init(control: ControlNavegador) {
            self.control = control
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            marcar(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            marcar(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            marcar(false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            marcar(false)
        }

        /// Enlaces que abren otra ventana (target="_blank"): se abren en la misma.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func marcar(_ cargando: Bool) {
            Task { @MainActor [weak self] in
                self?.control.cargando = cargando
            }
        }
    }
}

enum LectorReserva {
    /// Texto visible de la página (y de sus marcos, si son de la misma web).
    static let guion = """
    (function() {
      var partes = [document.body ? document.body.innerText : ''];
      var marcos = document.querySelectorAll('iframe');
      for (var i = 0; i < marcos.length; i++) {
        try {
          var d = marcos[i].contentDocument;
          if (d && d.body) { partes.push(d.body.innerText); }
        } catch (e) {}
      }
      return partes.join('\\n');
    })();
    """

    /// Números de vuelo de las aerolíneas conocidas ("IB 3140", "VY1234"…), en orden y sin repetir.
    static func numerosDeVuelo(en texto: String) -> [String] {
        let conocidos = Set(BuscadorVuelos.webs.map { $0.iata })
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Z0-9]{2})\s?(\d{1,4})\b"#) else { return [] }
        var encontrados: [String] = []
        let rango = NSRange(texto.startIndex..., in: texto)
        for m in regex.matches(in: texto, range: rango) {
            guard let r1 = Range(m.range(at: 1), in: texto),
                  let r2 = Range(m.range(at: 2), in: texto) else { continue }
            let codigo = String(texto[r1])
            guard conocidos.contains(codigo) else { continue }
            var numero = String(texto[r2])
            while numero.count > 1 && numero.hasPrefix("0") { numero.removeFirst() }
            let vuelo = codigo + numero
            if !encontrados.contains(vuelo) { encontrados.append(vuelo) }
        }
        return encontrados
    }
}

// ============================================================================
// CLAVE GRATUITA PARA LOS HORARIOS (AeroDataBox en RapidAPI)
// ============================================================================

struct ClaveVuelosView: View {
    @EnvironmentObject var almacen: Almacen

    @State private var clave = ""
    @State private var probando = false
    @State private var resultado = ""
    @State private var resultadoBueno = false

    var body: some View {
        Form {
            Section {
                Text("1. Abre la web de abajo y crea una cuenta gratis en RapidAPI (con tu email).")
                Text("2. Suscríbete al plan «Basic» de AeroDataBox: es gratis y da para unas 200 búsquedas al mes.")
                Text("3. Copia tu clave («X-RapidAPI-Key») y pégala aquí.")
                if let url = URL(string: BuscadorVuelos.webClaveGratis) {
                    Link(destination: url) {
                        Label("Abrir AeroDataBox en RapidAPI", systemImage: "safari")
                    }
                }
            } header: {
                Text("Cómo conseguir la clave")
            } footer: {
                Text("El plan Basic es gratuito. Si en algún momento te pidiera una tarjeta, no sigas.")
            }

            Section {
                SecureField("Pega aquí la clave", text: $clave)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await probarYGuardar() }
                } label: {
                    HStack {
                        Text(probando ? "Comprobando…" : "Comprobar y guardar")
                        Spacer()
                        if probando { ProgressView() }
                    }
                }
                .disabled(clave.recortado.isEmpty || probando)

                if !resultado.isEmpty {
                    Text(resultado)
                        .font(.caption)
                        .foregroundStyle(resultadoBueno ? Color.green : Color.orange)
                }

                if !almacen.claveVuelos.isEmpty {
                    Button(role: .destructive) {
                        almacen.guardarClaveVuelos("")
                        clave = ""
                        resultadoBueno = true
                        resultado = "Clave quitada. Al buscar un vuelo solo se rellenarán la ruta y las ciudades."
                    } label: {
                        Text("Quitar la clave")
                    }
                }
            } header: {
                Text("Tu clave")
            } footer: {
                Text("Se guarda en vuestro espacio, así funciona en los dos iPhones. Al buscar solo se envían el nº de vuelo y el día.")
            }
        }
        .navigationTitle("Horarios de vuelos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if clave.isEmpty { clave = almacen.claveVuelos }
        }
    }

    private func probarYGuardar() async {
        probando = true
        resultado = ""
        // Se prueba con un vuelo cualquiera de mañana: lo que importa es si la clave entra.
        let prueba = await BuscadorVuelos.buscarHorario(numeroVuelo: "IB3140", fecha: Date().sumando(dias: 1), clave: clave)
        probando = false
        switch prueba {
        case .claveNoValida:
            resultadoBueno = false
            resultado = "Esa clave no funciona: revisa que esté bien copiada y que estés suscrito al plan Basic (gratis) de AeroDataBox."
        case .fallo(let texto):
            resultadoBueno = false
            resultado = texto + " Prueba otra vez en un rato."
        case .encontrados, .sinVuelo, .limiteAgotado:
            almacen.guardarClaveVuelos(clave)
            resultadoBueno = true
            resultado = "✅ Clave guardada. Al buscar un vuelo se rellenarán solas las horas y la duración."
        }
    }
}

/// Sección de Ajustes para activar los horarios automáticos.
struct SeccionClaveVuelos: View {
    @EnvironmentObject var almacen: Almacen

    var body: some View {
        Section {
            NavigationLink {
                ClaveVuelosView()
            } label: {
                HStack {
                    Label("Horarios de vuelos", systemImage: "airplane.circle")
                    Spacer()
                    Text(almacen.claveVuelos.isEmpty ? "Sin activar" : "Activados")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("Con una clave gratuita, al buscar un vuelo se rellenan solas la hora de salida y de llegada, las ciudades y la duración.")
        }
    }
}
