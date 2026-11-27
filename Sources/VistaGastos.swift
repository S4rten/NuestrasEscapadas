import SwiftUI

// ============================================================================
// PESTAÑA GASTOS: reparto 50/50 por persona (cada gasto guarda el ID de quien pagó)
// ============================================================================

struct GastosSecciones: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    let escapada: Escapada
    @Binding var hoja: HojaDetalle?

    var body: some View {
        let gastos = almacen.gastosDe(escapada.id)
        let resumen = ResumenGastos(gastos: gastos, miId: sesion.miId, pagos: almacen.pagosDe(escapada.id))
        let pareja = almacen.nombreDePareja(miId: sesion.miId)
        let hayPareja = almacen.hayPareja(miId: sesion.miId)

        SeccionPresupuesto(escapada: escapada, gastado: resumen.total, hoja: $hoja)

        Section {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TOTAL DEL VIAJE")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(resumen.total.formatoDivisa())
                            .font(.title2.bold().monospacedDigit())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(sesion.miNombre): \(resumen.pagadoPorMi.formatoDivisa())")
                        Text("\(pareja): \(resumen.pagadoPorPareja.formatoDivisa())")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                if resumen.total > 0 && hayPareja {
                    HStack(spacing: 8) {
                        Image(systemName: abs(resumen.saldo) < 0.01 ? "checkmark.seal.fill" : "arrow.left.arrow.right.circle.fill")
                            .foregroundStyle(abs(resumen.saldo) < 0.01 ? Color.green : Color.accentColor)
                        Text(textoSaldo(resumen.saldo, pareja: pareja))
                            .font(.caption.bold())
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.vertical, 4)

            if hayPareja && abs(resumen.saldo) >= 0.01 {
                FilaSaldarCuentas(escapada: escapada, saldo: resumen.saldo)
            }

            ForEach(gastos) { gasto in
                filaGasto(gasto)
                    .contentShape(Rectangle())
                    .onTapGesture { hoja = .gasto(gasto) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrar(id: gasto.id, de: .gastos)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
            }

            Button {
                hoja = .gasto(nil)
            } label: {
                Label("Añadir gasto compartido", systemImage: "eurosign.circle.fill")
            }
        } header: {
            Text("Gastos compartidos")
        } footer: {
            Text("Por defecto se reparte a medias; al añadir un gasto podéis cambiar el reparto. Toca un gasto para editarlo y desliza para borrarlo.")
        }

        SeccionPagosPareja(escapada: escapada)

        if !gastos.isEmpty {
            SeccionGastosPorDia(escapada: escapada, gastos: gastos)
        }
    }

    private func textoSaldo(_ saldo: Double, pareja: String) -> String {
        if abs(saldo) < 0.01 {
            return "¡Estáis en paz!"
        } else if saldo > 0 {
            return "\(pareja) te debe \(saldo.formatoDivisa())"
        } else {
            return "Le debes \((-saldo).formatoDivisa()) a \(pareja)"
        }
    }

    /// "Todo de Ana", "Todo de Eric" o "Reparto 70 / 30" (nil si es a medias).
    private func textoRepartoConNombres(_ gasto: Gasto) -> String? {
        let pagueYo = gasto.pagadoPorId == sesion.miId
        let pagador = pagueYo ? sesion.miNombre : almacen.nombre(de: gasto.pagadoPorId, miId: sesion.miId)
        let otro = pagueYo ? almacen.nombreDePareja(miId: sesion.miId) : sesion.miNombre
        switch ModoReparto.para(gasto.porcentajePagador) {
        case .aMedias: return nil
        case .todoQuienPaga: return "Todo de \(pagador)"
        case .todoElOtro: return "Todo de \(otro)"
        case .personalizado: return textoRepartoCorto(gasto.porcentajePagador)
        }
    }

    private func filaGasto(_ gasto: Gasto) -> some View {
        HStack(spacing: 10) {
            Text(CategoriaGasto.icono(para: gasto.categoria))
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(gasto.concepto)
                    .font(.subheadline.weight(.medium))
                Text("\(gasto.categoria) · Pagó \(gasto.pagadoPorId == sesion.miId ? sesion.miNombre : almacen.nombre(de: gasto.pagadoPorId, miId: sesion.miId)) · \(gasto.fecha.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let reparto = textoRepartoConNombres(gasto) {
                    Text("⚖️ \(reparto)")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if gasto.codigoDivisa != "EUR" {
                    Text(gasto.importeOriginal.formatoDivisa(gasto.codigoDivisa))
                        .font(.subheadline.bold().monospacedDigit())
                    Text("≈ \(gasto.importe.formatoDivisa())")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(gasto.importe.formatoDivisa())
                        .font(.subheadline.bold().monospacedDigit())
                }
            }
        }
    }
}

// ============================================================================
// FORMULARIO DE GASTO (crear y editar)
// ============================================================================

struct FormularioGasto: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @EnvironmentObject var divisas: ServicioDivisas
    @Environment(\.dismiss) private var dismiss

    let escapada: Escapada
    private let existente: Gasto?

    @State private var concepto: String
    @State private var importeTexto: String
    @State private var divisa: String
    @State private var tasaTexto: String
    @State private var pagadoPorId: String
    @State private var categoria: String
    @State private var fecha: Date
    @State private var porcentajePagador: Double = 50
    @State private var modoReparto: ModoReparto = .aMedias
    // Tasa oficial del día del gasto (BCE) para gastos de días anteriores.
    @State private var tasaSugerida = ""              // la última tasa puesta sola (si la cambias tú, no se pisa)
    @State private var tasaDelDia: TasaDelDia? = nil
    @State private var cambioFechaODivisa = false

    /// `fechaInicial`: para gastos nuevos creados desde un día concreto del itinerario.
    init(escapada: Escapada, existente: Gasto?, fechaInicial: Date? = nil) {
        self.escapada = escapada
        self.existente = existente
        if let g = existente {
            _concepto = State(initialValue: g.concepto)
            _importeTexto = State(initialValue: String(format: "%.2f", g.importeOriginal))
            _divisa = State(initialValue: g.codigoDivisa)
            _tasaTexto = State(initialValue: textoTasa(g.tasaAEuros))
            _pagadoPorId = State(initialValue: g.pagadoPorId)
            _categoria = State(initialValue: g.categoria)
            _fecha = State(initialValue: g.fecha)
            _porcentajePagador = State(initialValue: g.porcentajePagador)
            _modoReparto = State(initialValue: ModoReparto.para(g.porcentajePagador))
        } else {
            _concepto = State(initialValue: "")
            _importeTexto = State(initialValue: "")
            _divisa = State(initialValue: escapada.divisaDestino)
            _tasaTexto = State(initialValue: "")
            _pagadoPorId = State(initialValue: "")
            _categoria = State(initialValue: "Comida")
            _fecha = State(initialValue: fechaInicial.map { $0.combinando(horaDe: Date()) } ?? Date())
        }
    }

    private func numero(_ texto: String) -> Double? {
        Double(texto.recortado.replacingOccurrences(of: ",", with: "."))
    }

    private var importe: Double { numero(importeTexto) ?? 0 }

    private var tasa: Double {
        divisa == "EUR" ? 1 : (numero(tasaTexto) ?? 0)
    }

    private var equivalenteEuros: Double { importe * tasa }

    private var puedeGuardar: Bool {
        !concepto.recortado.isEmpty && importe > 0 && tasa > 0
    }

    private var divisasSugeridas: [String] {
        var lista: [String] = []
        for codigo in ["EUR", escapada.divisaDestino, "USD", "GBP"] where !lista.contains(codigo) {
            lista.append(codigo)
        }
        return lista
    }

    private var pagadores: [Miembro] {
        var lista: [Miembro] = [Miembro(id: sesion.miId, nombre: sesion.miNombre)]
        for m in almacen.miembros where m.id != sesion.miId {
            lista.append(m)
        }
        // Si se edita un gasto pagado por alguien que ya no está en la lista, se conserva.
        if !pagadoPorId.isEmpty && !lista.contains(where: { $0.id == pagadoPorId }) {
            lista.append(Miembro(id: pagadoPorId, nombre: "Pareja"))
        }
        return lista
    }

    var body: some View {
        NavigationStack {
            Form {
                if existente == nil {
                    SeccionEscanearTicket { t in
                        aplicarTicket(t)
                    }
                }

                Section("Detalle del gasto") {
                    TextField("Concepto (ej: Cena en el centro)", text: $concepto)

                    TextField("Importe en \(divisa) (ej: 42,50)", text: $importeTexto)
                        .keyboardType(.decimalPad)

                    NavigationLink {
                        SelectorDivisaView(seleccion: $divisa, sugeridas: divisasSugeridas)
                    } label: {
                        HStack {
                            Text("Divisa")
                            Spacer()
                            Text("\(divisa) · \(DivisaInfo(id: divisa).nombre)")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if divisa != "EUR" {
                    Section {
                        HStack {
                            Text("1 \(divisa) =")
                            TextField("0,00", text: $tasaTexto)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("€")
                        }
                        if importe > 0 && tasa > 0 {
                            HStack {
                                Text("Equivale a")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(equivalenteEuros.formatoDivisa())
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    } header: {
                        Text("Conversión a euros")
                    } footer: {
                        Text(textoPieTasa)
                    }
                }

                Section {
                    Picker("¿Quién pagó?", selection: $pagadoPorId) {
                        ForEach(pagadores) { p in
                            Text(p.nombre).tag(p.id)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Reparto", selection: repartoPorPersona) {
                        Text("A medias").tag("aMedias")
                        Text(sesion.miNombre).tag(sesion.miId)
                        Text(otraPersona.nombre).tag(otraPersona.id)
                        Text(ModoReparto.personalizado.etiqueta).tag("personalizado")
                    }

                    if modoReparto == .personalizado {
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(value: $porcentajePagador, in: 0...100, step: 5)
                            Text("Quien paga: \(Int(porcentajePagador.rounded())) % · La otra persona: \(100 - Int(porcentajePagador.rounded())) %")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Categoría", selection: $categoria) {
                        ForEach(CategoriaGasto.allCases, id: \.rawValue) { c in
                            Text("\(c.icono) \(c.rawValue)").tag(c.rawValue)
                        }
                    }

                    DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                } header: {
                    Text("Reparto y categoría")
                } footer: {
                    if let texto = textoPieReparto {
                        Text(texto)
                    }
                }
            }
            .onChange(of: modoReparto) { _, nuevo in
                if let p = nuevo.porcentaje { porcentajePagador = p }
            }
            .onChange(of: pagadoPorId) { anterior, nuevo in
                // "Todo de Ana" sigue siendo de Ana aunque cambie quién pagó.
                guard !anterior.isEmpty, anterior != nuevo else { return }
                if modoReparto == .todoQuienPaga {
                    modoReparto = .todoElOtro
                } else if modoReparto == .todoElOtro {
                    modoReparto = .todoQuienPaga
                }
            }
            .navigationTitle(existente == nil ? "Nuevo gasto" : "Editar gasto")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if existente == nil {
                    if pagadoPorId.isEmpty { pagadoPorId = sesion.miId }
                    aplicarTasaSugerida()
                }
            }
            .onChange(of: divisa) { _, _ in
                cambioFechaODivisa = true
                aplicarTasaSugerida()
            }
            .onChange(of: fecha) { _, _ in
                cambioFechaODivisa = true
            }
            .task(id: claveTasaDelDia) {
                await aplicarTasaDelDia()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existente == nil ? "Añadir" : "Guardar") { guardar() }
                        .disabled(!puedeGuardar)
                }
            }
        }
    }

    /// La otra persona del espacio (o quien pagó, si no he sido yo).
    private var otraPersona: Miembro {
        let pagador = pagadoPorId.isEmpty ? sesion.miId : pagadoPorId
        if pagador != sesion.miId {
            return pagadores.first(where: { $0.id == pagador })
                ?? Miembro(id: pagador, nombre: almacen.nombreDePareja(miId: sesion.miId))
        }
        return almacen.miembros.first(where: { $0.id != sesion.miId })
            ?? Miembro(id: "pareja", nombre: almacen.nombreDePareja(miId: sesion.miId))
    }

    /// Reparto por persona: "aMedias", el ID de quien carga con todo el gasto, o "personalizado".
    /// Por dentro se sigue guardando como parte de quien paga (porcentajePagador).
    private var repartoPorPersona: Binding<String> {
        Binding(
            get: {
                let pagador = pagadoPorId.isEmpty ? sesion.miId : pagadoPorId
                let otro = otraPersona.id
                switch modoReparto {
                case .aMedias: return "aMedias"
                case .personalizado: return "personalizado"
                case .todoQuienPaga: return pagador == sesion.miId ? sesion.miId : otro
                case .todoElOtro: return pagador == sesion.miId ? otro : sesion.miId
                }
            },
            set: { valor in
                let pagueYo = (pagadoPorId.isEmpty ? sesion.miId : pagadoPorId) == sesion.miId
                if valor == "aMedias" {
                    modoReparto = .aMedias
                } else if valor == "personalizado" {
                    modoReparto = .personalizado
                } else if valor == sesion.miId {
                    modoReparto = pagueYo ? .todoQuienPaga : .todoElOtro
                } else {
                    modoReparto = pagueYo ? .todoElOtro : .todoQuienPaga
                }
            }
        )
    }

    /// "A ti te tocan X € y a Ana Y €" según quién paga y el reparto elegido.
    private var textoPieReparto: String? {
        let total = equivalenteEuros
        guard total > 0 else { return nil }
        let pagador = pagadoPorId.isEmpty ? sesion.miId : pagadoPorId
        let parteQuienPaga = total * porcentajePagador / 100
        let parteOtro = total - parteQuienPaga
        let pareja = almacen.nombreDePareja(miId: sesion.miId)
        let miParte = pagador == sesion.miId ? parteQuienPaga : parteOtro
        let suParte = total - miParte
        return "Te tocan \(miParte.formatoDivisa()) y a \(pareja) \(suParte.formatoDivisa())."
    }

    private var textoPieTasa: String {
        if let t = tasaDelDia, tasaTexto == tasaSugerida {
            return "Tasa oficial del Banco Central Europeo del \(t.fechaLegible) (la del día del gasto). Si tu tarjeta aplicó otra, escribe la real."
        }
        if let fechaTasas = divisas.ultimaActualizacion {
            return "Tasa orientativa del \(fechaTasas.formatted(date: .abbreviated, time: .omitted)). Si tu tarjeta aplicó otra, escribe la real."
        }
        return "No hay tasa guardada todavía: escríbela tú (cuántos euros vale 1 \(divisa))."
    }

    private func aplicarTasaSugerida() {
        if divisa == "EUR" {
            tasaTexto = "1"
        } else if let t = divisas.tasaAEuros(de: divisa) {
            tasaTexto = textoTasa(t)
        } else {
            tasaTexto = ""
        }
        tasaSugerida = tasaTexto
        tasaDelDia = nil
    }

    /// Cambia cada vez que cambian la divisa o el día del gasto.
    private var claveTasaDelDia: String {
        "\(divisa)|\(Int(fecha.inicioDelDia.timeIntervalSince1970))"
    }

    /// Gasto de un día anterior: pone la tasa oficial del BCE de ese día (si no la has cambiado tú).
    private func aplicarTasaDelDia() async {
        guard divisa != "EUR" else { return }
        // En un gasto ya guardado no se toca la tasa, salvo que cambies la fecha o la divisa.
        if existente != nil && !cambioFechaODivisa { return }
        guard fecha.inicioDelDia < Date().inicioDelDia else {
            tasaDelDia = nil
            return
        }
        let codigo = divisa
        let dia = fecha
        guard let t = await ServicioTasasDelDia.compartido.tasa(de: codigo, dia: dia) else { return }
        // Si mientras tanto cambió algo, o escribiste tu propia tasa, no se pisa.
        guard codigo == divisa, Calendar.current.isDate(dia, inSameDayAs: fecha) else { return }
        guard tasaTexto.recortado.isEmpty || tasaTexto == tasaSugerida else { return }
        tasaTexto = textoTasa(t.tasa)
        tasaSugerida = tasaTexto
        tasaDelDia = t
    }

    /// Rellena el formulario con lo leído del ticket (solo lo que se ha podido leer).
    private func aplicarTicket(_ t: TicketLeido) {
        if let importe = t.importe {
            importeTexto = String(format: "%.2f", importe).replacingOccurrences(of: ".", with: ",")
        }
        if let comercio = t.comercio, concepto.recortado.isEmpty {
            concepto = comercio
        }
        if let f = t.fecha, escapada.diaDelViaje(para: f) != nil {
            fecha = f
        }
        if let c = t.categoria {
            categoria = c
        }
    }

    private func guardar() {
        var g = existente ?? Gasto()
        g.escapadaId = escapada.id
        g.concepto = concepto.recortado
        g.importeOriginal = importe
        g.codigoDivisa = divisa
        g.tasaAEuros = tasa
        g.importe = importe * tasa
        g.pagadoPorId = pagadoPorId.isEmpty ? sesion.miId : pagadoPorId
        g.categoria = categoria
        g.fecha = fecha
        g.porcentajePagador = min(max(porcentajePagador, 0), 100)
        almacen.guardar(g, en: .gastos)
        dismiss()
    }
}

// ============================================================================
// SELECTOR DE DIVISA (con buscador)
// ============================================================================

struct SelectorDivisaView: View {
    @Binding var seleccion: String
    let sugeridas: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var busqueda = ""

    private var filtradas: [DivisaInfo] {
        let t = busqueda.recortado.lowercased()
        if t.isEmpty { return Divisas.todas }
        return Divisas.todas.filter {
            $0.id.lowercased().contains(t) || $0.nombre.lowercased().contains(t)
        }
    }

    var body: some View {
        List {
            if busqueda.recortado.isEmpty {
                Section("Sugeridas") {
                    ForEach(sugeridas, id: \.self) { codigo in
                        fila(codigo)
                    }
                }
            }
            Section("Todas") {
                ForEach(filtradas) { divisa in
                    fila(divisa.id)
                }
            }
        }
        .searchable(text: $busqueda, prompt: "Buscar divisa (ej: CZK, yen)")
        .navigationTitle("Divisa")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fila(_ codigo: String) -> some View {
        Button {
            seleccion = codigo
            dismiss()
        } label: {
            HStack {
                Text(codigo)
                    .font(.body.monospaced())
                    .foregroundStyle(.primary)
                Text(DivisaInfo(id: codigo).nombre)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if seleccion == codigo {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
