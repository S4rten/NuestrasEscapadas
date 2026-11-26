import SwiftUI
import CoreLocation

// ============================================================================
// ESTADÍSTICAS GLOBALES Y PAÍSES VISITADOS
// Se abre desde la pestaña Recuerdos. Las escapadas antiguas que no tienen
// país guardado lo deducen de sus coordenadas la primera vez que se abre.
// ============================================================================

enum Paises {
    /// Países reconocidos por la ONU (193) + Vaticano y Palestina.
    static let totalMundo = 195

    static func bandera(_ iso: String) -> String {
        iso.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(127397 + $0.value) }
            .map { String($0) }
            .joined()
    }

    static func nombre(_ iso: String) -> String {
        Locale.current.localizedString(forRegionCode: iso) ?? iso
    }
}

private struct PaisVisitado: Identifiable {
    let id: String          // código ISO
    let viajes: Int
}

struct EstadisticasView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    @State private var completandoPaises = false

    /// Nunca se cuentan sorpresas que aún están ocultas para mí.
    private var visibles: [Escapada] {
        almacen.escapadas.filter { !$0.sorpresaOculta(para: sesion.miId) }
    }

    private var vividas: [Escapada] { visibles.filter { $0.yaVivida } }

    /// Para los países también cuenta el viaje en curso.
    private var visitadas: [Escapada] { visibles.filter { $0.haEmpezado } }

    private func gasto(_ e: Escapada) -> Double { almacen.totalGastado(e.id) }

    var body: some View {
        List {
            if vividas.isEmpty && visitadas.isEmpty {
                ContentUnavailableView(
                    "Aún no hay estadísticas",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Aparecerán cuando hayáis hecho vuestra primera escapada.")
                )
            } else {
                seccionNumeros
                seccionRecords
                seccionPorAno
                seccionPaises
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Estadísticas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await completarPaises() }
    }

    // MARK: En números

    private var seccionNumeros: some View {
        let totalGasto = vividas.reduce(0) { $0 + gasto($1) }
        let totalDias = vividas.reduce(0) { $0 + $1.totalDias }
        let conGasto = vividas.filter { gasto($0) > 0 }
        let diasConGasto = conGasto.reduce(0) { $0 + $1.totalDias }
        let gastoConGasto = conGasto.reduce(0) { $0 + gasto($1) }

        return Section("En números") {
            filaDato("Escapadas vividas", "\(vividas.count)")
            filaDato("Días de viaje", "\(totalDias)")
            filaDato("Total gastado", totalGasto.formatoDivisa())
            if !conGasto.isEmpty {
                filaDato("Gasto medio por viaje", (gastoConGasto / Double(conGasto.count)).formatoDivisa())
                filaDato("Coste medio por día", (diasConGasto > 0 ? gastoConGasto / Double(diasConGasto) : 0).formatoDivisa())
            }
        }
    }

    // MARK: Récords

    @ViewBuilder
    private var seccionRecords: some View {
        let conGasto = vividas.filter { gasto($0) > 0 }
        let masCaro = conGasto.max { gasto($0) < gasto($1) }
        let masBarato = conGasto.min { gasto($0) < gasto($1) }
        let masLargo = vividas.max { $0.totalDias < $1.totalDias }
        let mejorNota = vividas.filter { $0.valoracion.media != nil }
            .max { ($0.valoracion.media ?? 0) < ($1.valoracion.media ?? 0) }

        if masCaro != nil || masLargo != nil || mejorNota != nil {
            Section("Récords") {
                if let e = masCaro {
                    filaRecord("💸 El más caro", e, gasto(e).formatoDivisa())
                }
                if let e = masBarato, conGasto.count > 1 {
                    filaRecord("🪙 El más barato", e, gasto(e).formatoDivisa())
                }
                if let e = masLargo {
                    filaRecord("🗓️ El más largo", e, "\(e.totalDias) \(e.totalDias == 1 ? "día" : "días")")
                }
                if let e = mejorNota, let media = e.valoracion.media {
                    filaRecord("⭐️ Mejor nota", e, String(format: "%.1f", media))
                }
            }
        }
    }

    // MARK: Por año

    @ViewBuilder
    private var seccionPorAno: some View {
        let porAno = Dictionary(grouping: vividas) { Calendar.current.component(.year, from: $0.fechaInicio) }
        let anos = porAno.keys.sorted(by: >)

        if !anos.isEmpty {
            Section("Por año") {
                ForEach(anos, id: \.self) { ano in
                    let viajes = porAno[ano] ?? []
                    let dias = viajes.reduce(0) { $0 + $1.totalDias }
                    let total = viajes.reduce(0) { $0 + gasto($1) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(ano))
                                .font(.headline)
                            Text("\(viajes.count) \(viajes.count == 1 ? "escapada" : "escapadas") · \(dias) \(dias == 1 ? "día" : "días")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(total.formatoDivisa())
                            .font(.subheadline.bold().monospacedDigit())
                    }
                }
            }
        }
    }

    // MARK: Países visitados

    @ViewBuilder
    private var seccionPaises: some View {
        let conteo = Dictionary(grouping: visitadas.filter { !$0.paisCodigo.isEmpty }) { $0.paisCodigo.uppercased() }
        let paises = conteo.map { PaisVisitado(id: $0.key, viajes: $0.value.count) }
            .sorted { $0.viajes != $1.viajes ? $0.viajes > $1.viajes : Paises.nombre($0.id) < Paises.nombre($1.id) }
        let ciudades = Set(visitadas.map { $0.destino.recortado.lowercased() }).count
        let sinPais = visitadas.filter { $0.paisCodigo.isEmpty }.count

        Section {
            HStack {
                datoGrande("\(paises.count)", paises.count == 1 ? "país" : "países")
                Spacer()
                datoGrande("\(ciudades)", ciudades == 1 ? "ciudad" : "ciudades")
                Spacer()
                datoGrande(String(format: "%.1f %%", Double(paises.count) / Double(Paises.totalMundo) * 100), "del mundo")
            }
            .padding(.vertical, 4)

            ProgressView(value: Double(paises.count), total: Double(Paises.totalMundo))
                .tint(.green)

            ForEach(paises) { p in
                HStack(spacing: 12) {
                    Text(Paises.bandera(p.id))
                        .font(.title2)
                    Text(Paises.nombre(p.id))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(p.viajes) \(p.viajes == 1 ? "viaje" : "viajes")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if completandoPaises {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Buscando el país de las escapadas antiguas…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if sinPais > 0 {
                Text("\(sinPais) \(sinPais == 1 ? "escapada no tiene" : "escapadas no tienen") país porque no se localizó el destino. Edítalas y elige el destino de la lista de sugerencias.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Países visitados")
        }
    }

    // MARK: Piezas

    private func filaDato(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo)
            Spacer()
            Text(valor)
                .font(.subheadline.bold().monospacedDigit())
        }
    }

    private func filaRecord(_ titulo: String, _ e: Escapada, _ valor: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("\(e.icono) \(e.titulo)")
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            Text(valor)
                .font(.subheadline.bold().monospacedDigit())
        }
    }

    private func datoGrande(_ valor: String, _ etiqueta: String) -> some View {
        VStack(spacing: 2) {
            Text(valor)
                .font(.title2.bold().monospacedDigit())
            Text(etiqueta)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Deduce y guarda el país de las escapadas que tienen coordenadas pero no país.
    private func completarPaises() async {
        let pendientes = almacen.escapadas.filter {
            $0.paisCodigo.isEmpty && $0.latitud != nil && $0.longitud != nil
        }
        guard !pendientes.isEmpty else { return }
        completandoPaises = true
        let geocoder = CLGeocoder()
        // Apple limita las búsquedas seguidas: como mucho 20 por vez.
        for e in pendientes.prefix(20) {
            guard let lat = e.latitud, let lon = e.longitud else { continue }
            if let marcas = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)),
               let iso = marcas.first?.isoCountryCode {
                almacen.actualizar(e.id, en: .escapadas, campos: ["paisCodigo": iso])
            }
        }
        completandoPaises = false
    }
}
