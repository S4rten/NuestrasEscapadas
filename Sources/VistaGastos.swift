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
        let resumen = ResumenGastos(gastos: gastos, miId: sesion.miId)
        let pareja = almacen.nombreDePareja(miId: sesion.miId)
        let hayPareja = almacen.hayPareja(miId: sesion.miId)

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
                        Text("Yo: \(resumen.pagadoPorMi.formatoDivisa())")
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
            Text("Todo se reparte a partes iguales. Toca un gasto para editarlo y desliza para borrarlo.")
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

    private func filaGasto(_ gasto: Gasto) -> some View {
        HStack(spacing: 10) {
            Text(CategoriaGasto.icono(para: gasto.categoria))
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(gasto.concepto)
                    .font(.subheadline.weight(.medium))
                Text("\(gasto.categoria) · Pagó \(gasto.pagadoPorId == sesion.miId ? "yo" : almacen.nombre(de: gasto.pagadoPorId, miId: sesion.miId)) · \(gasto.fecha.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    init(escapada: Escapada, existente: Gasto?) {
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
        } else {
            _concepto = State(initialValue: "")
            _importeTexto = State(initialValue: "")
            _divisa = State(initialValue: escapada.divisaDestino)
            _tasaTexto = State(initialValue: "")
            _pagadoPorId = State(initialValue: "")
            _categoria = State(initialValue: "Comida")
            _fecha = State(initialValue: Date())
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
        var lista: [Miembro] = [Miembro(id: sesion.miId, nombre: "Yo")]
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

                Section("Reparto y categoría") {
                    Picker("¿Quién pagó?", selection: $pagadoPorId) {
                        ForEach(pagadores) { p in
                            Text(p.nombre).tag(p.id)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Categoría", selection: $categoria) {
                        ForEach(CategoriaGasto.allCases, id: \.rawValue) { c in
                            Text("\(c.icono) \(c.rawValue)").tag(c.rawValue)
                        }
                    }

                    DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
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
                aplicarTasaSugerida()
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

    private var textoPieTasa: String {
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
