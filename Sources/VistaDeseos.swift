import SwiftUI
import UIKit

// ============================================================================
// WISHLIST DE LA PAREJA: sitios y experiencias que queréis hacer algún día.
//  · Cada uno marca sus ganas (👍 / 👎) y se ordena por lo que más os apetece.
//  · "Sorpréndeme": sortea un deseo (los que más os gustan tienen más papeletas).
//  · Se convierte en escapada con un toque, y se detecta solo si ya está
//    planeado o si ya lo habéis vivido.
//  · Todo se sincroniza en tiempo real entre los dos iPhones.
// ============================================================================

private enum OrdenDeseos: String, CaseIterable, Identifiable {
    case ganas = "Más ganas"
    case recientes = "Recientes"

    var id: String { rawValue }
}

private enum HojaDeseo: Identifiable {
    case nuevo
    case editar(Deseo)
    case convertir(Deseo)

    var id: String {
        switch self {
        case .nuevo: return "nuevo"
        case .editar(let d): return "editar-\(d.id)"
        case .convertir(let d): return "convertir-\(d.id)"
        }
    }
}

struct DeseosView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    @State private var textoNuevo = ""
    @State private var categoriaNueva: CategoriaDeseo = .destino
    @State private var filtro: CategoriaDeseo? = nil
    @State private var orden: OrdenDeseos = .ganas
    @State private var verCumplidos = false
    @State private var hoja: HojaDeseo? = nil

    @State private var elegido: Deseo? = nil
    @State private var sorteando = false
    @State private var celebracion: String? = nil

    // MARK: Datos

    private var filtrados: [Deseo] {
        almacen.deseos.filter { filtro == nil || $0.categoria == filtro }
    }

    private var pendientes: [Deseo] {
        let lista = filtrados.filter { !$0.cumplido }
        switch orden {
        case .ganas:
            return lista.sorted { a, b in
                let pa = puntuacion(a.votos)
                let pb = puntuacion(b.votos)
                return pa != pb ? pa > pb : a.creadoEn > b.creadoEn
            }
        case .recientes:
            return lista.sorted { $0.creadoEn > $1.creadoEn }
        }
    }

    private var cumplidos: [Deseo] {
        filtrados.filter { $0.cumplido }
            .sorted { ($0.cumplidoEn ?? $0.creadoEn) > ($1.cumplidoEn ?? $1.creadoEn) }
    }

    private var gustanALosDos: Int {
        guard almacen.miembros.count >= 2 else { return 0 }
        return almacen.deseos.filter { d in
            !d.cumplido && almacen.miembros.allSatisfy { d.votos[$0.id] == 1 }
        }.count
    }

    /// Escapada que encaja con el deseo (por destino). Nunca destapa sorpresas ocultas.
    private func escapadaRelacionada(_ d: Deseo) -> Escapada? {
        let base = d.lugar.isEmpty && d.categoria == .destino ? d.titulo : d.lugar
        let clave = base.recortado.lowercased()
        guard clave.count >= 3 else { return nil }
        return almacen.escapadas
            .filter { !$0.sorpresaOculta(para: sesion.miId) }
            .sorted { $0.fechaInicio > $1.fechaInicio }
            .first { e in
                let destino = e.destino.recortado.lowercased()
                guard !destino.isEmpty else { return false }
                return destino.contains(clave) || clave.contains(destino)
            }
    }

    // MARK: Vista

    var body: some View {
        List {
            if let texto = celebracion {
                Section {
                    Text(texto)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .listRowBackground(Color.green.opacity(0.15))
                }
            }

            seccionResumen

            if elegido != nil || sorteando {
                seccionSorteo
            }

            seccionAnadir

            Section {
                filtros
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                if pendientes.isEmpty {
                    Text(almacen.deseos.isEmpty
                         ? "Aún no hay deseos. Apuntad ese sitio del que siempre habláis 😉"
                         : "No hay deseos pendientes con este filtro.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(pendientes) { d in
                    fila(d)
                }
            } header: {
                HStack {
                    Text("Pendientes (\(pendientes.count))")
                    Spacer()
                    Picker("Orden", selection: $orden) {
                        ForEach(OrdenDeseos.allCases) { o in
                            Text(o.rawValue).tag(o)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
            } footer: {
                if !pendientes.isEmpty {
                    Text("Marca tus ganas con 👍 / 👎. Desliza a la derecha para marcarlo como cumplido y a la izquierda para borrarlo. Mantén pulsado para más opciones.")
                }
            }

            if !cumplidos.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: $verCumplidos) {
                        ForEach(cumplidos) { d in
                            filaCumplido(d)
                        }
                    } label: {
                        Label("Cumplidos (\(cumplidos.count))", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .animation(.default, value: almacen.deseos.map { "\($0.id)\($0.cumplido)\(puntuacion($0.votos))" })
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    hoja = .nuevo
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
        }
        .sheet(item: $hoja) { h in
            switch h {
            case .nuevo:
                FormularioDeseo(existente: nil)
            case .editar(let d):
                FormularioDeseo(existente: d)
            case .convertir(let d):
                NuevaEscapadaView(
                    existente: nil,
                    tituloSugerido: d.titulo,
                    destinoSugerido: d.lugar.isEmpty ? d.titulo : d.lugar,
                    iconoSugerido: d.categoria.emoji
                )
            }
        }
    }

    // MARK: Secciones

    private var seccionResumen: some View {
        let total = almacen.deseos.count
        let hechos = almacen.deseos.filter { $0.cumplido }.count

        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(hechos)")
                        .font(.largeTitle.bold().monospacedDigit())
                    Text("de \(total) deseos cumplidos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(value: Double(hechos), total: Double(max(total, 1)))
                    .tint(.green)
                if gustanALosDos > 0 {
                    Text("❤️ \(gustanALosDos) \(gustanALosDos == 1 ? "deseo os apetece" : "deseos os apetecen") a los dos")
                        .font(.caption.bold())
                        .foregroundStyle(.pink)
                }
                Button {
                    sortear()
                } label: {
                    Label(sorteando ? "Sorteando…" : "Sorpréndeme: ¿qué hacemos ahora?", systemImage: "dice.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sorteando || almacen.deseos.allSatisfy { $0.cumplido })
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var seccionSorteo: some View {
        Section {
            if let d = elegido {
                VStack(spacing: 10) {
                    Text(d.categoria.emoji)
                        .font(.system(size: 54))
                    Text(d.titulo)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    if !d.lugar.isEmpty {
                        Text("📍 \(d.lugar)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !sorteando {
                        HStack {
                            Button {
                                hoja = .convertir(d)
                            } label: {
                                Label("Planear escapada", systemImage: "calendar.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                sortear()
                            } label: {
                                Label("Otra", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                        Button("Cerrar") {
                            withAnimation { elegido = nil }
                        }
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .scaleEffect(sorteando ? 0.95 : 1)
            }
        } header: {
            Text(sorteando ? "🎲 Sorteando…" : "🎲 ¡Os toca!")
        }
    }

    private var seccionAnadir: some View {
        Section {
            HStack(spacing: 10) {
                Menu {
                    ForEach(CategoriaDeseo.allCases) { c in
                        Button("\(c.emoji) \(c.nombre)") { categoriaNueva = c }
                    }
                } label: {
                    Text(categoriaNueva.emoji)
                        .font(.title2)
                }
                TextField("Nuevo deseo (ej: ver auroras boreales)", text: $textoNuevo)
                    .onSubmit { anadirRapido() }
                Button {
                    anadirRapido()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(textoNuevo.recortado.isEmpty)
            }
        } header: {
            Text("Añadir a la wishlist")
        } footer: {
            Text("Toca el emoji para elegir el tipo. Con el botón + de arriba puedes añadir también el lugar y notas.")
        }
    }

    private var filtros: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipFiltro(titulo: "Todos", activo: filtro == nil) { filtro = nil }
                ForEach(CategoriaDeseo.allCases) { c in
                    let cuantos = almacen.deseos.filter { $0.categoria == c && !$0.cumplido }.count
                    if cuantos > 0 || filtro == c {
                        chipFiltro(titulo: "\(c.emoji) \(c.nombre) · \(cuantos)", activo: filtro == c) {
                            filtro = (filtro == c) ? nil : c
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chipFiltro(titulo: String, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button {
            withAnimation { accion() }
        } label: {
            Text(titulo)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(activo ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                .foregroundStyle(activo ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Filas

    private func fila(_ d: Deseo) -> some View {
        let relacionada = escapadaRelacionada(d)

        return HStack(alignment: .top, spacing: 12) {
            Text(d.categoria.emoji)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(d.titulo)
                    .font(.subheadline.weight(.semibold))
                if !d.lugar.isEmpty {
                    Text("📍 \(d.lugar)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !d.notas.isEmpty {
                    Text(d.notas)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let e = relacionada {
                    if e.yaVivida {
                        Button {
                            cumplir(d)
                        } label: {
                            Label("Ya lo vivisteis en «\(e.titulo)». ¿Marcar cumplido?", systemImage: "checkmark.circle")
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.green)
                    } else {
                        Chip(texto: "📅 Planeado: \(e.titulo)", color: .blue)
                    }
                }
                BotonesVoto(coleccion: .deseos, id: d.id, votos: d.votos)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { hoja = .editar(d) }
        .swipeActions(edge: .leading) {
            Button {
                cumplir(d)
            } label: {
                Label("Cumplido", systemImage: "checkmark.seal.fill")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                almacen.borrar(id: d.id, de: .deseos)
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                hoja = .convertir(d)
            } label: {
                Label("Convertir en escapada", systemImage: "calendar.badge.plus")
            }
            Button {
                hoja = .editar(d)
            } label: {
                Label("Editar", systemImage: "pencil")
            }
            Button {
                cumplir(d)
            } label: {
                Label("Marcar como cumplido", systemImage: "checkmark.seal")
            }
        }
    }

    private func filaCumplido(_ d: Deseo) -> some View {
        HStack(spacing: 12) {
            Text(d.categoria.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.titulo)
                    .font(.subheadline)
                    .strikethrough()
                if let fecha = d.cumplidoEn {
                    Text("Cumplido el \(fecha.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
        .swipeActions(edge: .leading) {
            Button {
                almacen.actualizar(d.id, en: .deseos, campos: ["cumplido": false, "cumplidoEn": NSNull()])
            } label: {
                Label("Pendiente", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                almacen.borrar(id: d.id, de: .deseos)
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
    }

    // MARK: Acciones

    private func anadirRapido() {
        let t = textoNuevo.recortado
        guard !t.isEmpty else { return }
        var d = Deseo()
        d.titulo = t
        d.categoria = categoriaNueva
        d.creadoPorId = sesion.miId
        d.creadoEn = Date()
        d.votos = [sesion.miId: 1]          // quien lo apunta, lo quiere
        almacen.guardar(d, en: .deseos)
        textoNuevo = ""
    }

    private func cumplir(_ d: Deseo) {
        almacen.actualizar(d.id, en: .deseos, campos: ["cumplido": true, "cumplidoEn": Date()])
        if elegido?.id == d.id { elegido = nil }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { celebracion = "🎉 ¡Deseo cumplido: \(d.titulo)!" }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { celebracion = nil }
        }
    }

    /// Sorteo con "ruleta": va cambiando rápido y frena. Más ganas = más papeletas.
    private func sortear() {
        let candidatos = almacen.deseos.filter { !$0.cumplido && (filtro == nil || $0.categoria == filtro) }
        let todos = candidatos.isEmpty ? almacen.deseos.filter { !$0.cumplido } : candidatos
        guard !todos.isEmpty else { return }
        sorteando = true
        let golpe = UISelectionFeedbackGenerator()
        Task {
            for paso in 0..<14 {
                withAnimation(.easeInOut(duration: 0.08)) { elegido = todos.randomElement() }
                golpe.selectionChanged()
                try? await Task.sleep(nanoseconds: UInt64(50_000_000 + paso * 18_000_000))
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                elegido = sorteoPonderado(todos)
                sorteando = false
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func sorteoPonderado(_ lista: [Deseo]) -> Deseo? {
        // 👎👎 = 1 papeleta · sin votos = 3 · 👍👍 = 5
        let pesos = lista.map { max(1, 3 + puntuacion($0.votos)) }
        let total = pesos.reduce(0, +)
        guard total > 0 else { return lista.randomElement() }
        var tirada = Int.random(in: 0..<total)
        for (i, peso) in pesos.enumerated() {
            if tirada < peso { return lista[i] }
            tirada -= peso
        }
        return lista.last
    }
}

// ============================================================================
// FORMULARIO: nuevo deseo o edición
// ============================================================================

struct FormularioDeseo: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let existente: Deseo?

    @State private var titulo = ""
    @State private var lugar = ""
    @State private var notas = ""
    @State private var categoria: CategoriaDeseo = .destino
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tipo") {
                    Picker("Tipo", selection: $categoria) {
                        ForEach(CategoriaDeseo.allCases) { c in
                            Text("\(c.emoji) \(c.nombre)").tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("¿Qué queréis hacer?") {
                    TextField("Ej: Dormir en un iglú", text: $titulo)
                }

                Section {
                    TextField("Lugar (opcional, ej: Laponia)", text: $lugar)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Si pones el lugar, al convertirlo en escapada ya saldrá como destino y la app detectará cuando lo tengáis planeado.")
                }

                Section("Notas") {
                    TextField("Mejor época, precio aproximado, enlaces…", text: $notas, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existente == nil ? "Nuevo deseo" : "Editar deseo")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: cargar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(titulo.recortado.isEmpty)
                }
            }
        }
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        guard let d = existente else { return }
        titulo = d.titulo
        lugar = d.lugar
        notas = d.notas
        categoria = d.categoria
    }

    private func guardar() {
        if let d = existente {
            // Solo estos campos: así no se pisan los votos del otro.
            almacen.actualizar(d.id, en: .deseos, campos: [
                "titulo": titulo.recortado,
                "lugar": lugar.recortado,
                "notas": notas.recortado,
                "categoria": categoria.rawValue
            ])
        } else {
            var d = Deseo()
            d.titulo = titulo.recortado
            d.lugar = lugar.recortado
            d.notas = notas.recortado
            d.categoria = categoria
            d.creadoPorId = sesion.miId
            d.creadoEn = Date()
            d.votos = [sesion.miId: 1]
            almacen.guardar(d, en: .deseos)
        }
        dismiss()
    }
}
