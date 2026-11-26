import SwiftUI

// ============================================================================
// ACTIVIDAD RECIENTE: "Laura añadió 2 gastos y un deseo".
//  · Campana en Próximas con un punto rojo si tu pareja ha hecho algo nuevo.
//  · Punto en cada escapada con cambios que aún no has visto.
//  · Lo "visto" se guarda en cada iPhone (no se sincroniza).
//  · Nunca destapa nada de una sorpresa oculta para ti.
// ============================================================================

@MainActor
final class VistoReciente: ObservableObject {
    static let compartido = VistoReciente()

    private static let claveMarcas = "escapadas_visto_v1"
    private static let claveBase = "escapadas_visto_base_v1"
    private static let general = "__general__"

    @Published private(set) var marcas: [String: Date] = [:]
    /// Primera vez que se usó esta función en este iPhone: lo anterior cuenta como visto.
    private let base: Date

    private init() {
        let d = UserDefaults.standard
        let inicio: Date
        if let guardada = d.object(forKey: VistoReciente.claveBase) as? Date {
            inicio = guardada
        } else {
            inicio = Date()
            d.set(inicio, forKey: VistoReciente.claveBase)
        }
        base = inicio
        if let bruto = d.dictionary(forKey: VistoReciente.claveMarcas) as? [String: Double] {
            marcas = bruto.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    func ultimaVista(escapadaId: String) -> Date {
        max(marcas[escapadaId] ?? base, base)
    }

    var ultimaVistaGeneral: Date {
        max(marcas[VistoReciente.general] ?? base, base)
    }

    func marcarVista(escapadaId: String) {
        marcas[escapadaId] = Date()
        guardar()
    }

    func marcarGeneral() {
        marcas[VistoReciente.general] = Date()
        guardar()
    }

    private func guardar() {
        UserDefaults.standard.set(marcas.mapValues { $0.timeIntervalSince1970 }, forKey: VistoReciente.claveMarcas)
    }
}

extension Almacen {
    /// Novedades de la pareja (no las mías), de la más reciente a la más antigua.
    func novedadesDePareja(miId: String) -> [Novedad] {
        novedades.filter { $0.autorId != miId }.sorted { $0.fecha > $1.fecha }
    }

    func hayNovedades(escapadaId: String, miId: String, desde: Date) -> Bool {
        novedades.contains { $0.autorId != miId && $0.escapadaId == escapadaId && $0.fecha > desde }
    }

    /// Texto que se puede enseñar: si es de una sorpresa oculta para mí, sin detalles.
    func textoVisible(_ n: Novedad, miId: String) -> (icono: String, texto: String, contexto: String) {
        if let e = escapada(n.escapadaId) {
            if e.sorpresaOculta(para: miId) {
                return ("🎁", "preparó algo para vuestro plan sorpresa", "")
            }
            let contexto = n.texto.hasPrefix("creó la escapada") ? "" : "\(e.icono) \(e.titulo)"
            return (n.icono, n.texto, contexto)
        }
        return (n.icono, n.texto, "")
    }
}

/// Grupo de novedades seguidas del mismo tipo (ej: 12 cosas añadidas a la maleta).
private struct GrupoNovedad: Identifiable {
    let id: String
    let primera: Novedad
    var cantidad: Int
}

struct NovedadesView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var visto = VistoReciente.compartido

    @State private var incluirMias = false
    /// Se fija al abrir para que lo "nuevo" no desaparezca mientras miras la lista.
    @State private var corte: Date? = nil

    private func agrupar(_ lista: [Novedad]) -> [GrupoNovedad] {
        var grupos: [GrupoNovedad] = []
        for n in lista {
            if var ultimo = grupos.last,
               ultimo.primera.autorId == n.autorId,
               ultimo.primera.escapadaId == n.escapadaId,
               ultimo.primera.icono == n.icono,
               ultimo.primera.fecha.timeIntervalSince(n.fecha) < 10 * 60 {
                ultimo.cantidad += 1
                grupos[grupos.count - 1] = ultimo
            } else {
                grupos.append(GrupoNovedad(id: n.id, primera: n, cantidad: 1))
            }
        }
        return grupos
    }

    var body: some View {
        let todas = (incluirMias ? almacen.novedades.sorted { $0.fecha > $1.fecha } : almacen.novedadesDePareja(miId: sesion.miId))
        let limite = corte ?? visto.ultimaVistaGeneral
        let nuevas = agrupar(todas.filter { $0.fecha > limite })
        let antiguas = agrupar(todas.filter { $0.fecha <= limite })
        let pareja = almacen.nombreDePareja(miId: sesion.miId)

        NavigationStack {
            List {
                Section {
                    Picker("Mostrar", selection: $incluirMias) {
                        Text("De \(pareja)").tag(false)
                        Text("Todo").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                if todas.isEmpty {
                    ContentUnavailableView(
                        "Sin novedades",
                        systemImage: "bell.slash",
                        description: Text("Aquí verás lo que añada \(pareja): gastos, planes, deseos, billetes…")
                    )
                }

                if !nuevas.isEmpty {
                    Section("Nuevo") {
                        ForEach(nuevas) { g in fila(g, nueva: true) }
                    }
                }
                if !antiguas.isEmpty {
                    Section("Últimos 30 días") {
                        ForEach(antiguas) { g in fila(g, nueva: false) }
                    }
                }
            }
            .navigationTitle("Actividad reciente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .onAppear {
                if corte == nil { corte = visto.ultimaVistaGeneral }
                visto.marcarGeneral()
            }
        }
    }

    private func fila(_ g: GrupoNovedad, nueva: Bool) -> some View {
        let t = almacen.textoVisible(g.primera, miId: sesion.miId)
        let autor = g.primera.autorId == sesion.miId ? "Tú" : almacen.nombre(de: g.primera.autorId, miId: sesion.miId)
        let extra = g.cantidad > 1 ? " y \(g.cantidad - 1) más" : ""

        return HStack(alignment: .top, spacing: 12) {
            Text(t.icono)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                (Text(autor).bold() + Text(" \(t.texto)\(extra)"))
                    .font(.subheadline)
                HStack(spacing: 6) {
                    if !t.contexto.isEmpty {
                        Text(t.contexto)
                            .lineLimit(1)
                        Text("·")
                    }
                    Text(g.primera.fecha, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if nueva {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
    }
}

/// Campana para la barra de arriba, con punto rojo si hay algo nuevo de tu pareja.
struct BotonNovedades: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @ObservedObject private var visto = VistoReciente.compartido
    let accion: () -> Void

    var body: some View {
        let limite = visto.ultimaVistaGeneral
        let hayNuevas = almacen.novedades.contains { $0.autorId != sesion.miId && $0.fecha > limite }

        Button(action: accion) {
            Image(systemName: hayNuevas ? "bell.badge.fill" : "bell")
                .symbolRenderingMode(hayNuevas ? .multicolor : .monochrome)
                .font(.title3)
        }
        .accessibilityLabel(hayNuevas ? "Actividad reciente: hay novedades" : "Actividad reciente")
    }
}

/// Punto rojo en una escapada con cambios de tu pareja que aún no has visto.
struct PuntoNovedad: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @ObservedObject private var visto = VistoReciente.compartido
    let escapadaId: String

    var body: some View {
        if almacen.hayNovedades(escapadaId: escapadaId, miId: sesion.miId, desde: visto.ultimaVista(escapadaId: escapadaId)) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .accessibilityLabel("Novedades sin ver")
        }
    }
}
