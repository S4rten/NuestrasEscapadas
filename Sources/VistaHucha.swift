import SwiftUI
import UIKit

// ============================================================================
// HUCHA: ahorro común para la próxima escapada. Un objetivo ("Japón: 3.000 €"),
// cada uno apunta lo que mete y se ve el progreso y cuándo llegaréis.
// (Solo se apunta: el dinero no se mueve desde la app.)
// ============================================================================

extension Almacen {
    var huchasActivas: [Hucha] {
        huchas.filter { !$0.cerrada }.sorted { $0.creadaEn < $1.creadaEn }
    }
}

/// Cálculos de una hucha (progreso, ritmo, fecha estimada).
struct ResumenHucha {
    let ahorrado: Double
    let objetivo: Double
    let fechaEstimada: Date?
    let porMesNecesario: Double?

    init(hucha: Hucha, aportaciones: [Aportacion]) {
        ahorrado = aportaciones.reduce(0) { $0 + $1.importe }
        objetivo = hucha.objetivo
        let falta = max(0, hucha.objetivo - ahorrado)

        // Ritmo: lo ahorrado desde la primera aportación (mínimo 2 semanas para no exagerar).
        if falta > 0, ahorrado > 0, let primera = aportaciones.map({ $0.fecha }).min() {
            let dias = max(14, Date().timeIntervalSince(primera) / 86_400)
            let porDia = ahorrado / dias
            fechaEstimada = porDia > 0 ? Date().addingTimeInterval(falta / porDia * 86_400) : nil
        } else {
            fechaEstimada = nil
        }

        if falta > 0, let limite = hucha.fechaObjetivo, limite > Date() {
            let meses = max(1, Date().distance(to: limite) / (30.44 * 86_400))
            porMesNecesario = falta / meses
        } else {
            porMesNecesario = nil
        }
    }

    var progreso: Double { objetivo > 0 ? min(1, max(0, ahorrado / objetivo)) : 0 }
    var falta: Double { max(0, objetivo - ahorrado) }
    var conseguido: Bool { objetivo > 0 && ahorrado >= objetivo }
}

// MARK: - Tarjeta en Próximas

struct TarjetaHucha: View {
    @EnvironmentObject var almacen: Almacen

    var body: some View {
        NavigationLink {
            HuchasView()
        } label: {
            if let h = almacen.huchasActivas.first {
                let r = ResumenHucha(hucha: h, aportaciones: almacen.aportacionesDe(hucha: h.id))
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(h.emoji) \(h.titulo)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(r.conseguido ? "🎉 ¡Conseguido!" : "\(Int((r.progreso * 100).rounded())) %")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    ProgressView(value: r.progreso)
                        .tint(r.conseguido ? .green : .accentColor)
                    Text("\(r.ahorrado.formatoDivisa()) de \(r.objetivo.formatoDivisa())\(almacen.huchasActivas.count > 1 ? " · \(almacen.huchasActivas.count) huchas" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                HStack(spacing: 10) {
                    Text("🐷")
                        .font(.title3)
                    Text("Empezad una hucha para la próxima escapada")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lista de huchas

struct HuchasView: View {
    @EnvironmentObject var almacen: Almacen
    @State private var creando = false

    var body: some View {
        let cerradas = almacen.huchas.filter { $0.cerrada }.sorted { $0.creadaEn > $1.creadaEn }

        List {
            if almacen.huchas.isEmpty {
                ContentUnavailableView {
                    Label("Sin huchas", systemImage: "banknote")
                } description: {
                    Text("Poneos un objetivo (por ejemplo «Japón: 3.000 €») y apuntad lo que va metiendo cada uno.")
                } actions: {
                    Button("Crear hucha") { creando = true }
                        .buttonStyle(.borderedProminent)
                }
            }

            if !almacen.huchasActivas.isEmpty {
                Section("Ahorrando") {
                    ForEach(almacen.huchasActivas) { h in
                        NavigationLink {
                            DetalleHuchaView(huchaId: h.id)
                        } label: {
                            fila(h)
                        }
                    }
                }
            }

            if !cerradas.isEmpty {
                Section("Terminadas") {
                    ForEach(cerradas) { h in
                        NavigationLink {
                            DetalleHuchaView(huchaId: h.id)
                        } label: {
                            fila(h)
                                .opacity(0.6)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hucha")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creando = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $creando) {
            FormularioHucha(existente: nil)
        }
    }

    private func fila(_ h: Hucha) -> some View {
        let r = ResumenHucha(hucha: h, aportaciones: almacen.aportacionesDe(hucha: h.id))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(h.emoji) \(h.titulo)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(r.ahorrado.formatoDivisa()) / \(r.objetivo.formatoDivisa())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: r.progreso)
                .tint(r.conseguido ? .green : .accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detalle de una hucha

struct DetalleHuchaView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss
    let huchaId: String

    @State private var importeTexto = ""
    @State private var nota = ""
    @State private var sacar = false
    @State private var editando = false
    @State private var confirmandoBorrado = false
    @State private var convirtiendo = false

    private func numero(_ texto: String) -> Double {
        Double(texto.recortado.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        if let h = almacen.huchas.first(where: { $0.id == huchaId }) {
            contenido(h)
        } else {
            ContentUnavailableView("Esta hucha ya no existe", systemImage: "questionmark.folder")
        }
    }

    @ViewBuilder
    private func contenido(_ h: Hucha) -> some View {
        let aportaciones = almacen.aportacionesDe(hucha: h.id)
        let r = ResumenHucha(hucha: h, aportaciones: aportaciones)

        List {
            Section {
                VStack(spacing: 10) {
                    Text(h.emoji)
                        .font(.system(size: 54))
                    Text(r.ahorrado.formatoDivisa())
                        .font(.largeTitle.bold().monospacedDigit())
                        .contentTransition(.numericText())
                    Text("de \(r.objetivo.formatoDivisa())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: r.progreso)
                        .tint(r.conseguido ? .green : .accentColor)
                        .scaleEffect(x: 1, y: 2)
                        .padding(.vertical, 6)
                    if r.conseguido {
                        Text("🎉 ¡Lo habéis conseguido!")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Text("Faltan \(r.falta.formatoDivisa())")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                if !r.conseguido {
                    if let necesario = r.porMesNecesario, let limite = h.fechaObjetivo {
                        Label("Para llegar al \(limite.formatted(date: .abbreviated, time: .omitted)) necesitáis \(necesario.formatoDivisa()) al mes (\((necesario / 2).formatoDivisa()) cada uno).", systemImage: "calendar")
                            .font(.caption)
                    }
                    if let estimada = r.fechaEstimada {
                        Label("A este ritmo llegaréis hacia \(estimada.formatted(.dateTime.month(.wide).year())).", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                    }
                }
            }

            if !h.cerrada {
                Section {
                    Picker("Movimiento", selection: $sacar) {
                        Text("Meter").tag(false)
                        Text("Sacar").tag(true)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        TextField("Importe en €", text: $importeTexto)
                            .keyboardType(.decimalPad)
                        ForEach([10, 20, 50], id: \.self) { rapido in
                            Button("+\(rapido)") {
                                importeTexto = String(format: "%.2f", numero(importeTexto) + Double(rapido))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    TextField("Nota (opcional)", text: $nota)

                    Button {
                        aportar(h)
                    } label: {
                        Label(sacar ? "Apuntar que he sacado" : "Apuntar que he metido", systemImage: sacar ? "minus.circle.fill" : "plus.circle.fill")
                    }
                    .disabled(numero(importeTexto) <= 0)
                } header: {
                    Text("Apuntar")
                } footer: {
                    Text("La app solo lleva la cuenta: el dinero lo guardáis donde queráis (una cuenta común, un bote…).")
                }
            }

            let porPersona = Dictionary(grouping: aportaciones, by: { $0.autorId })
                .mapValues { $0.reduce(0) { $0 + $1.importe } }
            if porPersona.count > 0 {
                Section("Quién ha puesto qué") {
                    ForEach(porPersona.sorted { $0.value > $1.value }, id: \.key) { entrada in
                        HStack {
                            Text(almacen.nombre(de: entrada.key, miId: sesion.miId))
                            Spacer()
                            Text(entrada.value.formatoDivisa())
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }

            if !aportaciones.isEmpty {
                Section("Movimientos") {
                    ForEach(aportaciones) { a in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.nota.isEmpty ? (a.importe >= 0 ? "Aportación" : "Retirada") : a.nota)
                                    .font(.subheadline)
                                Text("\(almacen.nombre(de: a.autorId, miId: sesion.miId)) · \(a.fecha.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((a.importe >= 0 ? "+" : "−") + abs(a.importe).formatoDivisa())
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(a.importe >= 0 ? Color.green : Color.red)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                almacen.borrar(id: a.id, de: .aportaciones)
                            } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                if r.conseguido || r.ahorrado > 0 {
                    Button {
                        convirtiendo = true
                    } label: {
                        Label("Planear la escapada", systemImage: "airplane.departure")
                    }
                }
                Button {
                    almacen.actualizar(h.id, en: .huchas, campos: ["cerrada": !h.cerrada])
                } label: {
                    Label(h.cerrada ? "Volver a abrir la hucha" : "Dar la hucha por terminada", systemImage: h.cerrada ? "arrow.uturn.backward" : "checkmark.circle")
                }
                Button(role: .destructive) {
                    confirmandoBorrado = true
                } label: {
                    Label("Borrar hucha", systemImage: "trash")
                }
            }
        }
        .navigationTitle(h.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") { editando = true }
            }
        }
        .sheet(isPresented: $editando) {
            FormularioHucha(existente: h)
        }
        .sheet(isPresented: $convirtiendo) {
            NuevaEscapadaView(existente: nil, tituloSugerido: h.titulo, iconoSugerido: h.emoji)
        }
        .confirmationDialog("¿Borrar esta hucha?", isPresented: $confirmandoBorrado, titleVisibility: .visible) {
            Button("Borrar para los dos", role: .destructive) {
                almacen.borrarHucha(h)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrarán también todos sus movimientos.")
        }
    }

    private func aportar(_ h: Hucha) {
        let valor = numero(importeTexto)
        guard valor > 0 else { return }
        var a = Aportacion()
        a.huchaId = h.id
        a.autorId = sesion.miId
        a.importe = sacar ? -valor : valor
        a.nota = nota.recortado
        a.fecha = Date()
        almacen.guardar(a, en: .aportaciones)
        importeTexto = ""
        nota = ""
        sacar = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Crear o editar hucha

struct FormularioHucha: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let existente: Hucha?
    @State private var titulo = ""
    @State private var emoji = "🐷"
    @State private var objetivoTexto = ""
    @State private var conFecha = false
    @State private var fecha = Date().sumando(dias: 180)
    @State private var cargado = false

    private let emojis = ["🐷", "✈️", "🏝️", "🗼", "🏔️", "🍣", "🎢", "💍"]

    private var objetivo: Double {
        Double(objetivoTexto.recortado.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Objetivo") {
                    TextField("Para qué (ej: Japón)", text: $titulo)
                    TextField("Cantidad en €", text: $objetivoTexto)
                        .keyboardType(.decimalPad)
                    Picker("Icono", selection: $emoji) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).tag(e)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Fecha límite", isOn: $conFecha)
                    if conFecha {
                        DatePicker("Para el", selection: $fecha, in: Date()..., displayedComponents: .date)
                    }
                } footer: {
                    Text("Con fecha límite os diremos cuánto tenéis que ahorrar al mes.")
                }
            }
            .navigationTitle(existente == nil ? "Nueva hucha" : "Editar hucha")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !cargado, let h = existente else { return }
                cargado = true
                titulo = h.titulo
                emoji = h.emoji
                objetivoTexto = String(format: "%.0f", h.objetivo)
                if let f = h.fechaObjetivo {
                    conFecha = true
                    fecha = f
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existente == nil ? "Crear" : "Guardar") { guardar() }
                        .disabled(titulo.recortado.isEmpty || objetivo <= 0)
                }
            }
        }
    }

    private func guardar() {
        if let h = existente {
            almacen.actualizar(h.id, en: .huchas, campos: [
                "titulo": titulo.recortado,
                "emoji": emoji,
                "objetivo": objetivo,
                "fechaObjetivo": conFecha ? (fecha as Any) : (NSNull() as Any)
            ])
        } else {
            var h = Hucha()
            h.titulo = titulo.recortado
            h.emoji = emoji
            h.objetivo = objetivo
            h.fechaObjetivo = conFecha ? fecha : nil
            h.creadaPorId = sesion.miId
            h.creadaEn = Date()
            almacen.guardar(h, en: .huchas)
        }
        dismiss()
    }
}
