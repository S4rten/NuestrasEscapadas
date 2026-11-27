import SwiftUI

// ============================================================================
// MALETA SUGERIDA: lo que conviene llevar según lo que la app ya sabe del viaje
//  · el tiempo previsto (paraguas, abrigo, crema…),
//  · la ficha del país (adaptador, pasaporte, ESTA/ETA…),
//  · los planes y las ideas (bañador, calzado de montaña, ropa para templos…),
//  · las reservas (vuelos, trenes) y los días que dura.
// Lo que ya está en la checklist no se sugiere.
// ============================================================================

struct SugerenciaMaleta: Identifiable, Hashable {
    let texto: String
    let motivo: String
    var id: String { texto }
}

enum MaletaSugerida {
    /// Países donde vale la Tarjeta Sanitaria Europea.
    private static let conTarjetaSanitaria: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT",
        "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "SE", "IS", "LI", "NO", "CH", "GB"
    ]

    private static let tramites = ["ESTA", "eTA", "ETA", "K-ETA", "e-Visa", "eVisitor", "NZeTA", "TDAC", "IMUGA", "SG Arrival Card", "Check-MIG", "e-Ticket"]

    /// Palabras de los planes -> qué llevar.
    private static let reglasPlanes: [(palabras: [String], cosas: [String])] = [
        (["playa", "cala", "beach"], ["Bañador", "Toalla de playa", "Chanclas", "Crema solar"]),
        (["piscina", "spa", "termas", "balneario", "hammam", "aguas termales"], ["Bañador", "Chanclas"]),
        (["senderismo", "trekking", "montaña", "excursión", "volcán", "cascada", "ruta a pie", "subida"], ["Calzado de montaña", "Mochila pequeña", "Botella de agua"]),
        (["esquí", "ski", "nieve", "snowboard"], ["Ropa de nieve", "Ropa térmica", "Guantes"]),
        (["ópera", "teatro", "concierto", "gala", "michelin", "cena especial"], ["Ropa arreglada para la noche"]),
        (["catedral", "iglesia", "mezquita", "templo", "basílica", "vaticano", "monasterio", "sinagoga"], ["Ropa que cubra hombros y rodillas"]),
        (["barco", "crucero", "kayak", "ferry", "snorkel", "buceo", "velero"], ["Pastillas para el mareo", "Funda estanca para el móvil"]),
        (["parque de atracciones", "disney", "portaventura", "festival", "parque temático"], ["Batería externa", "Calzado cómodo"])
    ]

    @MainActor
    static func sugerencias(escapada: Escapada, almacen: Almacen, tiempo: ServicioTiempo) -> [SugerenciaMaleta] {
        var lista: [SugerenciaMaleta] = []
        func anadir(_ texto: String, _ motivo: String) {
            if !lista.contains(where: { $0.texto == texto }) {
                lista.append(SugerenciaMaleta(texto: texto, motivo: motivo))
            }
        }

        // 1) Tiempo previsto (solo cuando ya hay previsión, unos 15 días antes).
        if let lat = escapada.latitud, let lon = escapada.longitud {
            var diasLluvia: [Int] = []
            var nieve = false
            var despejado = false
            var minima: Double? = nil
            var maxima: Double? = nil
            for d in 1...escapada.totalDias {
                guard let p = tiempo.prevision(lat: lat, lon: lon, fecha: escapada.fechaParaDia(d)) else { continue }
                let lluvioso = (p.probabilidadLluvia ?? 0) >= 50 || (51...67).contains(p.codigo)
                    || (80...82).contains(p.codigo) || (95...99).contains(p.codigo)
                if lluvioso { diasLluvia.append(d) }
                if (71...77).contains(p.codigo) || (85...86).contains(p.codigo) { nieve = true }
                if p.codigo >= 0 && p.codigo <= 1 { despejado = true }
                if let mn = p.minima { minima = min(minima ?? mn, mn) }
                if let mx = p.maxima { maxima = max(maxima ?? mx, mx) }
            }
            if !diasLluvia.isEmpty {
                let dias = diasLluvia.map { String($0) }.joined(separator: ", ")
                anadir("Paraguas plegable", "☔ Lluvia prevista (día \(dias))")
                anadir("Chubasquero", "☔ Lluvia prevista (día \(dias))")
            }
            if nieve { anadir("Calzado impermeable", "🌨️ Nieve prevista") }
            if let mn = minima {
                let texto = "\(Int(mn.rounded()))°"
                if mn <= 5 {
                    anadir("Abrigo", "🥶 Mínimas de \(texto)")
                    anadir("Gorro, guantes y bufanda", "🥶 Mínimas de \(texto)")
                } else if mn <= 13 {
                    anadir("Chaqueta o sudadera", "🌬️ Mínimas de \(texto)")
                }
            }
            if let mx = maxima, mx >= 27 {
                let texto = "\(Int(mx.rounded()))°"
                anadir("Ropa fresca", "🥵 Máximas de \(texto)")
                anadir("Crema solar", "🥵 Máximas de \(texto)")
                anadir("Gorra o sombrero", "🥵 Máximas de \(texto)")
            }
            if despejado { anadir("Gafas de sol", "☀️ Días despejados") }
        }

        // 2) Ficha del país.
        let iso = escapada.paisCodigo.uppercased()
        if !iso.isEmpty && iso != "ES" {
            if let info = FichasPaises.datos[iso] {
                if info.necesitaAdaptador {
                    anadir("Adaptador de enchufe (tipo \(info.enchufes.joined(separator: "/")))", "🔌 Allí los enchufes son distintos")
                }
                let documentos = info.documentos
                if documentos.lowercased().contains("pasaporte") && !documentos.lowercased().hasPrefix("dni o pasaporte") {
                    anadir("Pasaporte en vigor", "🛂 \(documentos)")
                } else {
                    anadir("DNI o pasaporte", "🛂 \(documentos)")
                }
                for tramite in tramites where documentos.contains(tramite) {
                    anadir("\(tramite) aprobada (y guardada en el móvil)", "🛂 Hace falta para entrar")
                }
            } else {
                anadir("Pasaporte o DNI (mirad qué piden)", "🛂 Viaje fuera de España")
            }
            if conTarjetaSanitaria.contains(iso) {
                anadir("Tarjeta Sanitaria Europea", "🏥 Vale en \(Paises.nombre(iso))")
            } else {
                anadir("Seguro de viaje con asistencia médica", "🏥 Fuera de Europa la sanidad no está cubierta")
            }
        }
        if escapada.divisaDestino != "EUR" {
            let moneda = DivisaInfo(id: escapada.divisaDestino).nombre
            anadir("Algo de efectivo en \(escapada.divisaDestino)", "💶 Allí se paga en \(moneda)")
            anadir("Tarjeta sin comisiones en el extranjero", "💶 Allí se paga en \(moneda)")
        }

        // 3) Planes e ideas.
        let planes = almacen.actividadesDe(escapada.id).map { $0.nombreSitio } + almacen.ideasDe(escapada.id).map { $0.texto }
        for regla in reglasPlanes {
            guard let plan = planes.first(where: { p in
                let t = p.lowercased()
                return regla.palabras.contains(where: { t.contains($0) })
            }) else { continue }
            for cosa in regla.cosas {
                anadir(cosa, "📍 Plan: \(plan)")
            }
        }

        // 4) Reservas y duración.
        if !almacen.vuelosDe(escapada.id).isEmpty {
            anadir("Líquidos en bolsa (máx. 100 ml)", "✈️ Hay vuelos")
            anadir("Tarjetas de embarque en el móvil", "✈️ Hay vuelos")
        }
        if !almacen.trenesDe(escapada.id).isEmpty {
            anadir("Billetes de tren en el móvil", "🚂 Hay trenes")
        }
        if escapada.totalDias >= 4 {
            anadir("Ropa para \(escapada.totalDias) días (o plan para lavar)", "🧺 \(escapada.totalDias) días de viaje")
        }
        return lista
    }

    /// ¿Ya hay en la checklist algo que cubre esta sugerencia?
    static func yaEsta(_ texto: String, en existentes: [String]) -> Bool {
        let s = HorarioOSM.normalizar(texto)
        let clave = s.split(separator: " ").first.map(String.init) ?? s
        return existentes.contains { e in
            let n = HorarioOSM.normalizar(e)
            return n == s || (clave.count >= 5 && n.contains(clave))
        }
    }
}

struct SeccionMaletaSugerida: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @ObservedObject private var tiempo = ServicioTiempo.compartido
    let escapada: Escapada

    @State private var descartadas: Set<String> = []

    private var claveDescartadas: String { "escapadas_maleta_descartadas_\(escapada.id)" }

    var body: some View {
        let existentes = almacen.checklistDe(escapada.id).map { $0.texto }
        let pendientes = MaletaSugerida.sugerencias(escapada: escapada, almacen: almacen, tiempo: tiempo)
            .filter { !descartadas.contains($0.texto) && !MaletaSugerida.yaEsta($0.texto, en: existentes) }

        Group {
            // En una sorpresa aún oculta no se sugiere nada: delataría el destino.
            if !escapada.yaVivida && !escapada.sorpresaOculta(para: sesion.miId) && !pendientes.isEmpty {
                Section {
                    ForEach(pendientes) { s in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.texto)
                                    .font(.subheadline)
                                Text(s.motivo)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Button {
                                anadir([s.texto])
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                descartar(s.texto)
                            } label: {
                                Label("No hace falta", systemImage: "xmark")
                            }
                            .tint(.gray)
                        }
                    }
                    if pendientes.count > 1 {
                        Button {
                            anadir(pendientes.map { $0.texto })
                        } label: {
                            Label("Añadir todo a la checklist (\(pendientes.count))", systemImage: "suitcase.fill")
                        }
                    }
                } header: {
                    Text("🧳 Maleta sugerida para este viaje")
                } footer: {
                    Text("Según el tiempo previsto, el país, vuestros planes y las reservas. Desliza una sugerencia para descartarla.")
                }
            }
        }
        .onAppear {
            descartadas = Set(UserDefaults.standard.stringArray(forKey: claveDescartadas) ?? [])
        }
    }

    private func anadir(_ textos: [String]) {
        for (indice, texto) in textos.enumerated() {
            var tarea = ItemChecklist()
            tarea.escapadaId = escapada.id
            tarea.texto = texto
            tarea.asignadoAId = ""
            tarea.creadoEn = Date().addingTimeInterval(Double(indice) / 1000)
            almacen.guardar(tarea, en: .checklist)
        }
    }

    private func descartar(_ texto: String) {
        descartadas.insert(texto)
        UserDefaults.standard.set(Array(descartadas), forKey: claveDescartadas)
    }
}
