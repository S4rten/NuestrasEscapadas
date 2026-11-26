import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore

// ============================================================================
// BUSCADOR DE DESTINOS (autocompletado de Apple Maps)
// ============================================================================

final class BuscadorDestinos: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var sugerencias: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func buscar(_ texto: String) {
        let t = texto.recortado
        if t.count < 2 {
            sugerencias = []
            return
        }
        completer.queryFragment = t
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let resultados = completer.results
        DispatchQueue.main.async {
            self.sugerencias = resultados
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Sin sugerencias: el usuario puede escribir el destino a mano.
    }
}

// ============================================================================
// FORMULARIO: nueva escapada y edición de una existente
// ============================================================================

struct NuevaEscapadaView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let existente: Escapada?

    @State private var titulo = ""
    @State private var destino = ""
    @State private var latitud: Double? = nil
    @State private var longitud: Double? = nil
    @State private var divisa = "EUR"
    @State private var inicio = Date()
    @State private var fin = Date().sumando(dias: 2)
    @State private var icono = "✈️"
    @State private var esSorpresa = false
    @State private var pista = ""
    @State private var diasRevelar = 0

    @State private var destinoConfirmado = ""
    @State private var mostrarSugerencias = false
    @State private var guardando = false
    @State private var cargado = false
    @StateObject private var buscador = BuscadorDestinos()

    private let iconos = ["✈️", "🏔️", "🏖️", "🌿", "🍷", "🚗", "🎁", "🏙️", "🚆", "⛺️", "🎡", "🍕"]

    private var puedeEditarSorpresa: Bool {
        existente == nil || existente?.creadaPorId == sesion.miId
    }

    private var puedeGuardar: Bool {
        !titulo.recortado.isEmpty && !destino.recortado.isEmpty && !guardando
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Icono") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(iconos, id: \.self) { emoji in
                                Text(emoji)
                                    .font(.title)
                                    .padding(8)
                                    .background(icono == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .onTapGesture { icono = emoji }
                            }
                        }
                    }
                }

                Section("Nombre del plan") {
                    TextField("Ej: Escapada de invierno", text: $titulo)
                }

                Section {
                    TextField("¿A dónde vais? (ej: Praga)", text: $destino)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: destino) { _, nuevo in
                            if nuevo == destinoConfirmado {
                                mostrarSugerencias = false
                            } else {
                                latitud = nil
                                longitud = nil
                                mostrarSugerencias = true
                                buscador.buscar(nuevo)
                            }
                        }

                    if mostrarSugerencias && !buscador.sugerencias.isEmpty {
                        ForEach(Array(buscador.sugerencias.prefix(5)), id: \.self) { sugerencia in
                            Button {
                                elegir(sugerencia)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sugerencia.title)
                                        .foregroundStyle(.primary)
                                    if !sugerencia.subtitle.isEmpty {
                                        Text(sugerencia.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if latitud != nil && longitud != nil {
                        Label("Ubicación confirmada · moneda \(divisa)", systemImage: "mappin.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Destino")
                } footer: {
                    Text("Elige una sugerencia para que aparezca bien en el mapa y se proponga la moneda del país.")
                }

                Section("Fechas") {
                    DatePicker("Ida", selection: $inicio, displayedComponents: .date)
                    DatePicker("Vuelta", selection: $fin, in: inicio..., displayedComponents: .date)
                }

                if puedeEditarSorpresa {
                    Section {
                        Toggle("🎁 Plan sorpresa para mi pareja", isOn: $esSorpresa)
                        if esSorpresa {
                            TextField("Pista para tu pareja", text: $pista)
                            Stepper(
                                diasRevelar == 0
                                ? "Revelar el mismo día del viaje"
                                : "Revelar \(diasRevelar) \(diasRevelar == 1 ? "día" : "días") antes",
                                value: $diasRevelar,
                                in: 0...30
                            )
                        }
                    } footer: {
                        if esSorpresa {
                            Text("Tu pareja solo verá la pista hasta el día de la revelación.")
                        }
                    }
                }
            }
            .navigationTitle(existente == nil ? "Nueva escapada" : "Editar escapada")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { cargarSiHaceFalta() }
            .onChange(of: inicio) { _, nuevo in
                if fin < nuevo { fin = nuevo }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(!puedeGuardar)
                }
            }
        }
    }

    private func cargarSiHaceFalta() {
        guard !cargado else { return }
        cargado = true
        guard let e = existente else { return }
        titulo = e.titulo
        destinoConfirmado = e.destino
        destino = e.destino
        latitud = e.latitud
        longitud = e.longitud
        divisa = e.divisaDestino
        inicio = e.fechaInicio
        fin = e.fechaFin
        icono = e.icono
        esSorpresa = e.esSorpresa
        pista = e.pistaSorpresa
        diasRevelar = e.diasRevelarAntes
    }

    private func elegir(_ sugerencia: MKLocalSearchCompletion) {
        destinoConfirmado = sugerencia.title
        destino = sugerencia.title
        mostrarSugerencias = false
        Task {
            let peticion = MKLocalSearch.Request(completion: sugerencia)
            if let respuesta = try? await MKLocalSearch(request: peticion).start(),
               let item = respuesta.mapItems.first,
               destino == destinoConfirmado {
                latitud = item.placemark.coordinate.latitude
                longitud = item.placemark.coordinate.longitude
                if let moneda = Divisas.codigoParaPais(item.placemark.isoCountryCode) {
                    divisa = moneda
                }
            }
        }
    }

    private func guardar() {
        guardando = true
        Task {
            var lat = latitud
            var lon = longitud
            var moneda = divisa
            let destinoLimpio = destino.recortado

            // Si no se eligió ninguna sugerencia, intentamos localizar el destino escrito a mano.
            if lat == nil || lon == nil {
                if let marcas = try? await CLGeocoder().geocodeAddressString(destinoLimpio),
                   let marca = marcas.first,
                   let ubicacion = marca.location {
                    lat = ubicacion.coordinate.latitude
                    lon = ubicacion.coordinate.longitude
                    if let d = Divisas.codigoParaPais(marca.isoCountryCode) { moneda = d }
                }
            }

            let finCorregido = max(fin, inicio)

            if let e = existente {
                var campos: [String: Any] = [
                    "titulo": titulo.recortado,
                    "destino": destinoLimpio,
                    "divisaDestino": moneda,
                    "fechaInicio": inicio,
                    "fechaFin": finCorregido,
                    "icono": icono
                ]
                if let lat = lat, let lon = lon {
                    campos["latitud"] = lat
                    campos["longitud"] = lon
                } else {
                    campos["latitud"] = FieldValue.delete()
                    campos["longitud"] = FieldValue.delete()
                }
                if puedeEditarSorpresa {
                    campos["esSorpresa"] = esSorpresa
                    campos["pistaSorpresa"] = pista.recortado
                    campos["diasRevelarAntes"] = max(0, diasRevelar)
                }
                almacen.actualizar(e.id, en: .escapadas, campos: campos)
            } else {
                var nueva = Escapada()
                nueva.titulo = titulo.recortado
                nueva.destino = destinoLimpio
                nueva.latitud = lat
                nueva.longitud = lon
                nueva.divisaDestino = moneda
                nueva.fechaInicio = inicio
                nueva.fechaFin = finCorregido
                nueva.icono = icono
                nueva.esSorpresa = esSorpresa
                nueva.pistaSorpresa = esSorpresa ? pista.recortado : ""
                nueva.diasRevelarAntes = esSorpresa ? max(0, diasRevelar) : 0
                nueva.creadaPorId = sesion.miId
                nueva.creadaEn = Date()
                almacen.guardar(nueva, en: .escapadas)
            }
            dismiss()
        }
    }
}
