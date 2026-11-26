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
    /// Para crear una escapada desde una fecha especial (aniversario, cumpleaños…).
    var fechaSugerida: Date? = nil
    /// Para crear una escapada desde un deseo de la wishlist.
    var tituloSugerido: String? = nil
    var destinoSugerido: String? = nil
    var iconoSugerido: String? = nil

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
    @State private var presupuestoTexto = ""
    @State private var paisCodigo = ""

    @State private var destinoConfirmado = ""
    @State private var mostrarSugerencias = false
    @State private var guardando = false
    @State private var cargado = false
    @StateObject private var buscador = BuscadorDestinos()
    /// Escapada nueva: tras elegir la ida, la vuelta queda en ese mismo día y hay que elegirla.
    @State private var vueltaPorElegir = false
    @State private var confirmandoMismoDia = false

    /// Al cambiar la ida de una escapada nueva, la vuelta se coloca en ese día (no puede ser antes).
    private var fechaIda: Binding<Date> {
        Binding(
            get: { inicio },
            set: { nueva in
                inicio = nueva
                if existente == nil {
                    fin = nueva
                    vueltaPorElegir = true
                } else if fin < nueva {
                    fin = nueva
                }
            }
        )
    }

    private var fechaVuelta: Binding<Date> {
        Binding(
            get: { fin },
            set: { nueva in
                fin = max(nueva, inicio)
                vueltaPorElegir = false
            }
        )
    }

    private let iconos = ["✈️", "🏔️", "🏖️", "🌿", "🍷", "🚗", "🎁", "🏙️", "🚆", "⛺️", "🎡", "🍕"]

    private var puedeEditarSorpresa: Bool {
        existente == nil || existente?.creadaPorId == sesion.miId
    }

    private var puedeGuardar: Bool {
        !titulo.recortado.isEmpty && !destino.recortado.isEmpty && !guardando && presupuestoValido
    }

    /// Se puede fijar al crear el plan y cambiar hasta el día antes de salir.
    private var puedeEditarPresupuesto: Bool {
        existente?.presupuestoEditable ?? true
    }

    /// nil si el texto no es un número válido. Vacío = sin presupuesto (0).
    private var presupuesto: Double? {
        let t = presupuestoTexto.recortado.replacingOccurrences(of: ",", with: ".")
        if t.isEmpty { return 0 }
        guard let valor = Double(t), valor >= 0 else { return nil }
        return valor
    }

    private var presupuestoValido: Bool {
        !puedeEditarPresupuesto || presupuesto != nil
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
                                paisCodigo = ""
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

                Section {
                    DatePicker("Ida", selection: fechaIda, displayedComponents: .date)
                    DatePicker("Vuelta", selection: fechaVuelta, in: inicio..., displayedComponents: .date)
                } header: {
                    Text("Fechas")
                } footer: {
                    if vueltaPorElegir {
                        Text("Ahora elige la vuelta: a partir del \(inicio.formatted(date: .long, time: .omitted)) (los días anteriores están bloqueados).")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    if puedeEditarPresupuesto {
                        HStack {
                            TextField("Presupuesto total (opcional)", text: $presupuestoTexto)
                                .keyboardType(.decimalPad)
                            Text("€")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Text("Presupuesto")
                            Spacer()
                            Text((existente?.tienePresupuesto ?? false)
                                 ? (existente?.presupuesto ?? 0).formatoDivisa()
                                 : "Sin presupuesto")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Presupuesto")
                } footer: {
                    if puedeEditarPresupuesto {
                        if presupuesto == nil {
                            Text("Escribe solo el número (ej: 600 o 600,50).")
                                .foregroundStyle(.red)
                        } else {
                            Text("Lo que queréis gastar entre los dos en todo el viaje. Podéis cambiarlo hasta el día antes de salir.")
                        }
                    } else {
                        Text("El viaje ya ha empezado, así que el presupuesto ya no se puede cambiar.")
                    }
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
                    Button("Guardar") {
                        if vueltaPorElegir {
                            confirmandoMismoDia = true
                        } else {
                            guardar()
                        }
                    }
                    .disabled(!puedeGuardar)
                }
            }
            .confirmationDialog("¿Volvéis el mismo día?", isPresented: $confirmandoMismoDia, titleVisibility: .visible) {
                Button("Sí, ida y vuelta el mismo día") { guardar() }
                Button("Elegir la fecha de vuelta", role: .cancel) {}
            } message: {
                Text("Aún no has elegido la fecha de vuelta.")
            }
        }
    }

    private func cargarSiHaceFalta() {
        guard !cargado else { return }
        cargado = true
        guard let e = existente else {
            if let f = fechaSugerida {
                inicio = f
                fin = f.sumando(dias: 2)
            } else {
                // Nueva: la vuelta empieza en el día de la ida y hay que elegirla.
                fin = inicio
                vueltaPorElegir = true
            }
            if let t = tituloSugerido { titulo = t }
            if let d = destinoSugerido, !d.recortado.isEmpty { destino = d }
            if let i = iconoSugerido { icono = i }
            return
        }
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
        presupuestoTexto = e.tienePresupuesto ? textoImporte(e.presupuesto) : ""
        paisCodigo = e.paisCodigo
    }

    private func textoImporte(_ valor: Double) -> String {
        valor.rounded() == valor ? String(format: "%.0f", valor) : String(format: "%.2f", valor)
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
                paisCodigo = item.placemark.isoCountryCode ?? ""
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
            var pais = paisCodigo
            let destinoLimpio = destino.recortado

            // Si no se eligió ninguna sugerencia, intentamos localizar el destino escrito a mano.
            if lat == nil || lon == nil {
                if let marcas = try? await CLGeocoder().geocodeAddressString(destinoLimpio),
                   let marca = marcas.first,
                   let ubicacion = marca.location {
                    lat = ubicacion.coordinate.latitude
                    lon = ubicacion.coordinate.longitude
                    if let d = Divisas.codigoParaPais(marca.isoCountryCode) { moneda = d }
                    if let iso = marca.isoCountryCode { pais = iso }
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
                if puedeEditarPresupuesto, let p = presupuesto {
                    campos["presupuesto"] = p
                }
                if !pais.isEmpty {
                    campos["paisCodigo"] = pais
                } else if destinoLimpio != e.destino {
                    campos["paisCodigo"] = ""   // destino nuevo sin localizar: no dejar el país antiguo
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
                nueva.presupuesto = presupuesto ?? 0
                nueva.paisCodigo = pais
                almacen.guardar(nueva, en: .escapadas)
            }
            dismiss()
        }
    }
}
