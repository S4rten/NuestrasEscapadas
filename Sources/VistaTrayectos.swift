import SwiftUI
import MapKit
import CoreLocation

// ============================================================================
// TIEMPO ENTRE PLANES (pestaña Plan): entre dos planes situados en el mapa,
// cuánto se tarda andando (o en coche si está lejos) y aviso si no da tiempo.
// Los cálculos se guardan en memoria para no repetirlos.
// ============================================================================

struct ResultadoTrayecto {
    let segundos: TimeInterval
    let metros: Double
    let enCoche: Bool
    let aproximado: Bool        // sin respuesta de Apple Maps: estimado en línea recta

    var minutos: Int { max(1, Int((segundos / 60).rounded())) }

    var textoDistancia: String {
        metros >= 1000
            ? String(format: "%.1f km", metros / 1000).replacingOccurrences(of: ".", with: ",")
            : "\(Int((metros / 10).rounded() * 10)) m"
    }
}

@MainActor
final class Trayectos: ObservableObject {
    static let compartido = Trayectos()

    @Published private(set) var resultados: [String: ResultadoTrayecto] = [:]
    private var enCurso: Set<String> = []

    /// Más de esta distancia en línea recta: se calcula en coche en vez de andando.
    private static let limiteAndando: CLLocationDistance = 2_500

    private static func clave(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }

    func resultado(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> ResultadoTrayecto? {
        resultados[Self.clave(a, b)]
    }

    func calcular(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) async {
        let clave = Self.clave(a, b)
        guard resultados[clave] == nil, !enCurso.contains(clave) else { return }
        enCurso.insert(clave)
        defer { enCurso.remove(clave) }

        let recta = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let enCoche = recta > Self.limiteAndando

        let peticion = MKDirections.Request()
        peticion.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        peticion.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        peticion.transportType = enCoche ? .automobile : .walking

        if let eta = try? await MKDirections(request: peticion).calculateETA() {
            resultados[clave] = ResultadoTrayecto(segundos: eta.expectedTravelTime, metros: eta.distance,
                                                  enCoche: enCoche, aproximado: false)
        } else {
            // Sin conexión o sin ruta: estimación (las calles alargan ~30 % la línea recta).
            let metros = recta * 1.3
            let velocidad = enCoche ? 30_000.0 / 3600 : 4_800.0 / 3600   // m/s
            resultados[clave] = ResultadoTrayecto(segundos: metros / velocidad, metros: metros,
                                                  enCoche: enCoche, aproximado: true)
        }
    }
}

/// Fila pequeña entre dos planes: "🚶 12 min · 900 m" y aviso si no llegáis.
struct FilaTrayecto: View {
    @ObservedObject private var trayectos = Trayectos.compartido
    let desde: Actividad
    let hasta: Actividad

    private var origen: CLLocationCoordinate2D? {
        guard let lat = desde.latitud, let lon = desde.longitud else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var destino: CLLocationCoordinate2D? {
        guard let lat = hasta.latitud, let lon = hasta.longitud else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Minutos entre la hora de un plan y la del siguiente (si los dos tienen hora).
    private var hueco: Int? {
        guard let h1 = desde.hora, let h2 = hasta.hora, h2 > h1 else { return nil }
        return Int(h2.timeIntervalSince(h1) / 60)
    }

    var body: some View {
        if let a = origen, let b = destino {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 22)
                    .frame(width: 52)

                if let r = trayectos.resultado(a, b) {
                    Image(systemName: r.enCoche ? "car.fill" : "figure.walk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(r.aproximado ? "≈ " : "")\(r.minutos) min · \(r.textoDistancia)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    aviso(r)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Calculando trayecto…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .task(id: "\(a.latitude),\(a.longitude)>\(b.latitude),\(b.longitude)") {
                await trayectos.calcular(a, b)
            }
        }
    }

    @ViewBuilder
    private func aviso(_ r: ResultadoTrayecto) -> some View {
        if let hueco = hueco {
            if r.minutos >= hueco {
                Text("⚠️ No da tiempo")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
                    .help("Hacen falta \(r.minutos) min y solo hay \(hueco) entre un plan y otro.")
            } else if hueco - r.minutos < 20 {
                Text("⏱️ Vais justos")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
        }
    }
}

// ============================================================================
// PLAN B SI LLUEVE: cada plan es de interior o al aire libre (se adivina por
// el nombre si no lo marcáis). Si el día viene con lluvia, propone cambiar los
// planes al aire libre por otros de interior de otro día.
// ============================================================================

enum Ambiente {
    static let interior = "interior"
    static let exterior = "exterior"

    private static let palabrasInterior = [
        "museo", "museu", "musée", "museum", "galería", "galeria", "gallery", "exposición", "exposicion",
        "acuario", "aquarium", "catedral", "iglesia", "basílica", "basilica", "capilla", "mezquita", "sinagoga",
        "teatro", "ópera", "opera", "cine", "concierto", "musical", "restaurante", "cena", "comida", "almuerzo",
        "desayuno", "brunch", "café", "cafetería", "bar ", "cervecería", "vinoteca", "cata", "mercado",
        "centro comercial", "tienda", "compras", "outlet", "spa", "baños", "hammam", "termas", "masaje",
        "palacio", "castillo", "biblioteca", "planetario", "escape room", "bolera", "casino", "clase de",
        "taller", "tour gastronómico", "hotel"
    ]

    private static let palabrasExterior = [
        "parque", "park", "jardín", "jardin", "garden", "playa", "beach", "cala", "mirador", "paseo",
        "excursión", "excursion", "ruta", "senderismo", "trekking", "montaña", "lago", "río", "rio",
        "barco", "crucero", "kayak", "bici", "bicicleta", "zoo", "safari", "atracciones", "puerto",
        "plaza", "puente", "muralla", "ruinas", "acantilado", "cascada", "atardecer", "amanecer",
        "picnic", "free tour", "tour a pie", "golf", "esquí", "esqui", "snorkel", "buceo", "surf"
    ]

    /// "interior", "exterior" o "" si no se sabe.
    static func de(_ a: Actividad) -> String {
        if a.ambiente == interior || a.ambiente == exterior { return a.ambiente }
        let nombre = " \(a.nombreSitio.lowercased()) "
        if palabrasInterior.contains(where: { nombre.contains($0) }) { return interior }
        if palabrasExterior.contains(where: { nombre.contains($0) }) { return exterior }
        return ""
    }

    static func emoji(_ valor: String) -> String {
        switch valor {
        case interior: return "🏠"
        case exterior: return "🌳"
        default: return ""
        }
    }

    /// ¿Ese día se espera lluvia?
    static func lluvioso(_ p: PrevisionDia?) -> Bool {
        guard let p = p else { return false }
        if let prob = p.probabilidadLluvia, prob >= 60 { return true }
        switch p.codigo {
        case 61...67, 80...82, 95...99: return true
        default: return false
        }
    }

    /// Mueve un plan a otro día conservando su hora.
    @MainActor
    static func mover(_ a: Actividad, aDia dia: Int, escapada: Escapada, almacen: Almacen) {
        var campos: [String: Any] = ["dia": dia]
        if let h = a.hora {
            campos["hora"] = escapada.fechaParaDia(dia).combinando(horaDe: h)
        }
        almacen.actualizar(a.id, en: .actividades, campos: campos)
    }
}

struct SeccionPlanB: View {
    @EnvironmentObject var almacen: Almacen
    @ObservedObject private var tiempo = ServicioTiempo.compartido
    let escapada: Escapada
    let dia: Int

    private func prevision(_ d: Int) -> PrevisionDia? {
        guard let lat = escapada.latitud, let lon = escapada.longitud else { return nil }
        return tiempo.prevision(lat: lat, lon: lon, fecha: escapada.fechaParaDia(d))
    }

    private func textoProbabilidad(_ p: PrevisionDia?) -> String {
        guard let prob = p?.probabilidadLluvia else { return "" }
        return " (\(prob) %)"
    }

    /// "Día 3 ☀️ 10 %" para el menú de mover.
    private func textoDia(_ d: Int) -> String {
        guard let p = prevision(d) else { return "Día \(d) · sin previsión" }
        if let prob = p.probabilidadLluvia {
            return "Día \(d) \(p.emoji) \(prob) %"
        }
        return "Día \(d) \(p.emoji)"
    }

    var body: some View {
        let hoy = prevision(dia)
        let exteriores = almacen.actividadesDe(escapada.id)
            .filter { $0.dia == dia && !$0.completada && Ambiente.de($0) == Ambiente.exterior }

        if Ambiente.lluvioso(hoy), !exteriores.isEmpty {
            // Planes de interior de otros días que se podrían traer a este.
            let interiores = almacen.actividadesDe(escapada.id)
                .filter { $0.dia != dia && !$0.completada && !$0.todoElDia && Ambiente.de($0) == Ambiente.interior }
                .sorted { !Ambiente.lluvioso(prevision($0.dia)) && Ambiente.lluvioso(prevision($1.dia)) }
            // Días sin lluvia prevista para llevar los planes al aire libre.
            let diasSecos = (1...escapada.totalDias).filter { $0 != dia && !Ambiente.lluvioso(prevision($0)) }

            Section {
                ForEach(Array(exteriores.enumerated()), id: \.element.id) { i, plan in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🌳 \(plan.nombreSitio)")
                            .font(.subheadline.weight(.medium))

                        if i < interiores.count {
                            let cambio = interiores[i]
                            Button {
                                Ambiente.mover(plan, aDia: cambio.dia, escapada: escapada, almacen: almacen)
                                Ambiente.mover(cambio, aDia: dia, escapada: escapada, almacen: almacen)
                            } label: {
                                Label("Cambiar por 🏠 \(cambio.nombreSitio) (día \(cambio.dia))", systemImage: "arrow.left.arrow.right")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !diasSecos.isEmpty {
                            Menu {
                                ForEach(diasSecos, id: \.self) { d in
                                    Button {
                                        Ambiente.mover(plan, aDia: d, escapada: escapada, almacen: almacen)
                                    } label: {
                                        Text(textoDia(d))
                                    }
                                }
                            } label: {
                                Label("Mover a otro día", systemImage: "calendar")
                                    .font(.caption.bold())
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("☔️ Plan B: se espera lluvia" + textoProbabilidad(hoy))
            } footer: {
                Text(interiores.isEmpty
                     ? "No hay planes de interior en otros días para cambiar. Marca cada plan como interior o al aire libre manteniéndolo pulsado."
                     : "Se intercambian los días (cada plan conserva su hora). Marca cada plan como interior o al aire libre manteniéndolo pulsado.")
            }
        }
    }
}
