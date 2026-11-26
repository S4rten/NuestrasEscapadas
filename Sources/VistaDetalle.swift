import SwiftUI

// ============================================================================
// FICHA DE UNA ESCAPADA: cabecera + pestañas Plan · Reservas · Lista · Gastos · Recuerdo
// ============================================================================

enum PestanaDetalle: String, CaseIterable, Identifiable {
    case plan = "Plan"
    case reservas = "Reservas"
    case lista = "Lista"
    case gastos = "Gastos"
    case retos = "Retos"
    case recuerdo = "Recuerdo"

    var id: String { rawValue }

    var icono: String {
        switch self {
        case .plan: return "calendar.day.timeline.left"
        case .reservas: return "ticket.fill"
        case .lista: return "checklist"
        case .gastos: return "eurosign.circle.fill"
        case .retos: return "camera.fill"
        case .recuerdo: return "heart.text.square.fill"
        }
    }
}

/// Hoja (ventana modal) que puede abrirse desde la ficha.
enum HojaDetalle: Identifiable {
    case vuelo(Vuelo?)
    case tren(TrenViaje?)
    case alojamiento(Alojamiento?)
    case gasto(Gasto?)
    case gastoEnDia(Date)
    case camaraReto(Reto)
    case fotoReto(Reto)
    case editar

    var id: String {
        switch self {
        case .vuelo(let v): return "vuelo-\(v?.id ?? "nuevo")"
        case .tren(let t): return "tren-\(t?.id ?? "nuevo")"
        case .alojamiento(let a): return "alojamiento-\(a?.id ?? "nuevo")"
        case .gasto(let g): return "gasto-\(g?.id ?? "nuevo")"
        case .gastoEnDia(let fecha): return "gasto-dia-\(Int(fecha.timeIntervalSince1970))"
        case .camaraReto(let r): return "reto-camara-\(r.id)"
        case .fotoReto(let r): return "reto-foto-\(r.id)"
        case .editar: return "editar"
        }
    }
}

struct DetalleEscapadaView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let escapadaId: String

    @State private var pestana: PestanaDetalle = .plan
    @State private var hoja: HojaDetalle? = nil
    @State private var confirmandoBorrado = false

    var body: some View {
        if let escapada = almacen.escapada(escapadaId) {
            contenido(escapada)
        } else {
            ContentUnavailableView("Esta escapada ya no existe", systemImage: "questionmark.folder")
        }
    }

    @ViewBuilder
    private func contenido(_ e: Escapada) -> some View {
        let oculto = e.sorpresaOculta(para: sesion.miId)
        let activa: PestanaDetalle = (pestana == .recuerdo && !e.yaVivida) ? .plan : pestana
        let pestanasVisibles = PestanaDetalle.allCases.filter { $0 != .recuerdo || e.yaVivida }

        List {
            Section {
                cabecera(e, oculto: oculto)
            }

            if oculto {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "eye.slash.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("El destino, el itinerario y las reservas se mantienen ocultos hasta el \(e.fechaRevelacion.formatted(date: .long, time: .omitted)). ¡Que no se te escape nada!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Sorpresa protegida")
                }

                ListaSecciones(escapada: e, mostrarIdeas: false)
            } else {
                Section {
                    SelectorPestanas(pestanas: pestanasVisibles, seleccion: $pestana)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                switch activa {
                case .plan:
                    PlanSecciones(escapada: e, hoja: $hoja)
                case .reservas:
                    ReservasSecciones(escapada: e, hoja: $hoja)
                case .lista:
                    ListaSecciones(escapada: e, mostrarIdeas: true)
                case .gastos:
                    GastosSecciones(escapada: e, hoja: $hoja)
                case .retos:
                    RetosSecciones(escapada: e, hoja: $hoja)
                case .recuerdo:
                    RecuerdoSecciones(escapada: e)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(oculto ? "Plan sorpresa" : e.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !oculto {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            hoja = .editar
                        } label: {
                            Label("Editar escapada", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            confirmandoBorrado = true
                        } label: {
                            Label("Eliminar escapada", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $hoja) { h in
            hojaContenido(h, e)
        }
        .confirmationDialog("¿Eliminar esta escapada?", isPresented: $confirmandoBorrado, titleVisibility: .visible) {
            Button("Eliminar para los dos", role: .destructive) {
                almacen.borrarEscapada(e)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrarán las reservas, gastos, listas, retos con sus fotos y recuerdos de este viaje en los dos iPhones.")
        }
    }

    @ViewBuilder
    private func cabecera(_ e: Escapada, oculto: Bool) -> some View {
        HStack(spacing: 14) {
            Text(oculto ? "🎁" : e.icono)
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 4) {
                if oculto {
                    Text("Plan sorpresa")
                        .font(.title3.bold())
                    Text("🔒 Se revela el \(e.fechaRevelacion.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(e.pistaSorpresa.isEmpty ? "💡 Sin pista todavía" : "💡 Pista: \(e.pistaSorpresa)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(e.titulo)
                        .font(.title3.bold())
                    Text("📍 \(e.destino)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("🗓️ \(e.fechaInicio.formatted(date: .abbreviated, time: .omitted)) – \(e.fechaFin.formatted(date: .abbreviated, time: .omitted)) (\(e.totalDias) \(e.totalDias == 1 ? "día" : "días"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if e.esSorpresa {
                        Chip(texto: "🎁 Sorpresa · se revela el \(e.fechaRevelacion.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func hojaContenido(_ h: HojaDetalle, _ e: Escapada) -> some View {
        switch h {
        case .vuelo(let v):
            FormularioVuelo(escapada: e, existente: v)
        case .tren(let t):
            FormularioTren(escapada: e, existente: t)
        case .alojamiento(let a):
            FormularioAlojamiento(escapada: e, existente: a)
        case .gasto(let g):
            FormularioGasto(escapada: e, existente: g)
        case .gastoEnDia(let fecha):
            FormularioGasto(escapada: e, existente: nil, fechaInicial: fecha)
        case .camaraReto(let r):
            CamaraReto(reto: r)
                .ignoresSafeArea()
        case .fotoReto(let r):
            VisorFotoReto(retoId: r.id)
        case .editar:
            NuevaEscapadaView(existente: e)
        }
    }
}

struct SelectorPestanas: View {
    let pestanas: [PestanaDetalle]
    @Binding var seleccion: PestanaDetalle

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pestanas) { p in
                    Button {
                        seleccion = p
                    } label: {
                        Label(p.rawValue, systemImage: p.icono)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(seleccion == p ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(seleccion == p ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}
