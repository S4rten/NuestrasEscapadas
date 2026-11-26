import SwiftUI

// ============================================================================
// PLANTILLAS DE MALETA: listas típicas que se copian a la checklist del viaje,
// o copiar la checklist de otra escapada. Nunca duplica lo que ya está.
// ============================================================================

struct PlantillaMaleta: Identifiable {
    let id: String
    let icono: String
    let elementos: [String]

    static let todas: [PlantillaMaleta] = [
        PlantillaMaleta(id: "Playa", icono: "🏖️", elementos: [
            "Bañador", "Crema solar", "Toalla de playa", "Gafas de sol", "Chanclas",
            "Gorra o sombrero", "After sun", "Funda estanca para el móvil"
        ]),
        PlantillaMaleta(id: "Nieve", icono: "🏔️", elementos: [
            "Abrigo", "Guantes", "Gorro", "Bufanda", "Ropa térmica",
            "Botas impermeables", "Cacao para los labios", "Crema solar"
        ]),
        PlantillaMaleta(id: "Ciudad", icono: "🏙️", elementos: [
            "Calzado cómodo", "Batería externa", "Adaptador de enchufe", "Paraguas plegable",
            "Botella de agua", "Mochila pequeña", "Entradas descargadas en el móvil"
        ]),
        PlantillaMaleta(id: "Fin de semana", icono: "🧳", elementos: [
            "Cargadores", "Neceser", "Pijama", "Ropa para 2 días",
            "Medicamentos", "DNI o pasaporte", "Auriculares"
        ]),
        PlantillaMaleta(id: "Avión", icono: "✈️", elementos: [
            "DNI o pasaporte", "Tarjetas de embarque", "Líquidos en bolsa (máx. 100 ml)",
            "Cojín de viaje", "Auriculares", "Check-in online hecho"
        ])
    ]
}

struct SeccionPlantillasMaleta: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    let escapada: Escapada

    @State private var aviso: String? = nil

    /// Nunca se muestran sorpresas que aún están ocultas para mí.
    private var otrasConLista: [Escapada] {
        almacen.escapadas
            .filter { $0.id != escapada.id && !$0.sorpresaOculta(para: sesion.miId) }
            .filter { !almacen.checklistDe($0.id).isEmpty }
            .sorted { $0.fechaInicio > $1.fechaInicio }
    }

    var body: some View {
        Section {
            Menu {
                Section("Plantillas") {
                    ForEach(PlantillaMaleta.todas) { p in
                        Button("\(p.icono) \(p.id) (\(p.elementos.count))") {
                            anadir(p.elementos, origen: "la plantilla \(p.id)")
                        }
                    }
                }
                if !otrasConLista.isEmpty {
                    Section("Copiar de otra escapada") {
                        ForEach(otrasConLista) { e in
                            Button("\(e.icono) \(e.titulo)") {
                                anadir(almacen.checklistDe(e.id).map { $0.texto }, origen: e.titulo)
                            }
                        }
                    }
                }
            } label: {
                Label("Usar una plantilla de maleta", systemImage: "suitcase.fill")
            }

            if let aviso = aviso {
                Text(aviso)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Añade de golpe lo típico para playa, nieve, ciudad… Lo que ya esté en la lista no se repite.")
        }
    }

    private func anadir(_ textos: [String], origen: String) {
        let existentes = Set(almacen.checklistDe(escapada.id).map { $0.texto.recortado.lowercased() })
        var anadidos = 0
        var vistos = existentes
        for (indice, texto) in textos.enumerated() {
            let limpio = texto.recortado
            let clave = limpio.lowercased()
            guard !limpio.isEmpty, !vistos.contains(clave) else { continue }
            vistos.insert(clave)
            var tarea = ItemChecklist()
            tarea.escapadaId = escapada.id
            tarea.texto = limpio
            tarea.asignadoAId = ""
            // Un milisegundo de diferencia para que conserven el orden de la plantilla.
            tarea.creadoEn = Date().addingTimeInterval(Double(indice) / 1000)
            almacen.guardar(tarea, en: .checklist)
            anadidos += 1
        }
        aviso = anadidos == 0
            ? "Ya teníais todo lo de \(origen) en la lista."
            : "Añadidas \(anadidos) cosas de \(origen)."
    }
}
