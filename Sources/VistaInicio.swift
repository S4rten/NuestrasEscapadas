import SwiftUI

// ============================================================================
// PANTALLA PRINCIPAL: pestañas Próximas · Mapa · Recuerdos
// ============================================================================

struct InicioView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @ObservedObject private var red = MonitorConexion.compartido
    @State private var mostrandoNueva = false
    @State private var mostrandoAjustes = false

    var body: some View {
        TabView {
            NavigationStack {
                ProximasView(mostrandoNueva: $mostrandoNueva)
                    .navigationTitle("Escapadas")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                mostrandoAjustes = true
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(almacen.estado.estaBien && red.hayConexion ? Color.green : Color.orange)
                                        .frame(width: 8, height: 8)
                                    Text(sesion.miNombre)
                                        .font(.caption.bold())
                                }
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                mostrandoNueva = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            }
                        }
                    }
            }
            .tabItem { Label("Próximas", systemImage: "calendar") }

            NavigationStack {
                MapaView()
                    .navigationTitle("Nuestro mapa")
            }
            .tabItem { Label("Mapa", systemImage: "map.fill") }

            NavigationStack {
                YaVividoView()
                    .navigationTitle("Recuerdos")
            }
            .tabItem { Label("Recuerdos", systemImage: "heart.fill") }
        }
        .sheet(isPresented: $mostrandoNueva) {
            NuevaEscapadaView(existente: nil)
        }
        .sheet(isPresented: $mostrandoAjustes) {
            AjustesView()
        }
    }
}

// ============================================================================
// PRÓXIMAS
// ============================================================================

/// Fecha propuesta para crear una escapada desde una fecha especial.
private struct FechaParaNueva: Identifiable {
    let id = UUID()
    let fecha: Date
}

struct ProximasView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Binding var mostrandoNueva: Bool
    @State private var nuevaConFecha: FechaParaNueva? = nil

    private var proximas: [Escapada] {
        almacen.escapadas
            .filter { !$0.yaVivida }
            .sorted { $0.fechaInicio < $1.fechaInicio }
    }

    /// Viaje en curso (modo "Hoy"), si lo hay y no es una sorpresa oculta para mí.
    private var enCurso: Escapada? {
        proximas.first { $0.diaDeHoy != nil && !$0.sorpresaOculta(para: sesion.miId) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                BannerSinConexion()

                if case .error(let mensaje) = almacen.estado {
                    BannerError(mensaje: mensaje)
                }

                if let hoy = enCurso {
                    NavigationLink(value: hoy.id) {
                        TarjetaHoy(escapada: hoy)
                    }
                    .buttonStyle(.plain)
                }

                TarjetaFechaEspecial { fecha in
                    nuevaConFecha = FechaParaNueva(fecha: fecha)
                }

                if let primera = proximas.first {
                    NavigationLink(value: primera.id) {
                        TarjetaCuentaAtras(escapada: primera)
                    }
                    .buttonStyle(.plain)

                    let siguientes = Array(proximas.dropFirst())
                    if !siguientes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("EN EL HORIZONTE")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(siguientes) { escapada in
                                NavigationLink(value: escapada.id) {
                                    FilaEscapada(escapada: escapada)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else if !almacen.escapadasCargadas {
                    ProgressView("Conectando…")
                        .padding(.top, 60)
                } else {
                    ContentUnavailableView {
                        Label("Sin escapadas próximas", systemImage: "airplane")
                    } description: {
                        Text("Añade vuestro próximo viaje o plan de fin de semana.")
                    } actions: {
                        Button("Crear primer plan") {
                            mostrandoNueva = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationDestination(for: String.self) { id in
            DetalleEscapadaView(escapadaId: id)
        }
        .sheet(item: $nuevaConFecha) { f in
            NuevaEscapadaView(existente: nil, fechaSugerida: f.fecha)
        }
    }
}

struct TarjetaCuentaAtras: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    let escapada: Escapada

    var body: some View {
        let oculto = escapada.sorpresaOculta(para: sesion.miId)
        let objetivo = almacen.primeraSalida(de: escapada) ?? escapada.fechaInicio.inicioDelDia
        let tareas = almacen.checklistDe(escapada.id)
        let hechas = tareas.filter { $0.completado }.count
        let textoPista = escapada.pistaSorpresa.isEmpty
            ? "Se revela el \(escapada.fechaRevelacion.formatted(date: .abbreviated, time: .omitted))"
            : "💡 Pista: \(escapada.pistaSorpresa)"

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(oculto ? "🎁" : escapada.icono)
                    .font(.system(size: 34))
                    .frame(width: 58, height: 58)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Chip(texto: oculto ? "SORPRESA" : (escapada.haEmpezado ? "EN CURSO" : "PRÓXIMA PARADA"))
                    Text(oculto ? "Plan sorpresa" : escapada.titulo)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
                Spacer()
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(oculto ? "🔒 Destino secreto" : "📍 \(escapada.destino)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(oculto ? textoPista : escapada.fechaInicio.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if oculto {
                    Image(systemName: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Circle())
                }
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            TimelineView(.periodic(from: .now, by: 30)) { contexto in
                let resto = Int(objetivo.timeIntervalSince(contexto.date))
                if resto <= 0 {
                    Label("¡Ya estáis de escapada!", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    let dias = resto / 86400
                    let horas = (resto % 86400) / 3600
                    let minutos = (resto % 3600) / 60
                    HStack(spacing: 10) {
                        CajaContador(valor: "\(dias)", etiqueta: dias == 1 ? "Día" : "Días", destacado: true)
                        CajaContador(valor: String(format: "%02d", horas), etiqueta: "Horas", destacado: false)
                        CajaContador(valor: String(format: "%02d", minutos), etiqueta: "Minutos", destacado: false)
                    }
                }
            }

            VStack(spacing: 6) {
                HStack {
                    Text("Preparativos listos")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(hechas)/\(tareas.count)")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                }
                ProgressView(value: tareas.isEmpty ? 0 : Double(hechas) / Double(tareas.count))
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

struct CajaContador: View {
    let valor: String
    let etiqueta: String
    let destacado: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(valor)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(destacado ? Color.white : Color.primary)
            Text(etiqueta)
                .font(.caption2)
                .foregroundStyle(destacado ? Color.white.opacity(0.9) : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(destacado ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct FilaEscapada: View {
    @EnvironmentObject var sesion: Sesion
    let escapada: Escapada

    var body: some View {
        let oculto = escapada.sorpresaOculta(para: sesion.miId)
        let dias = escapada.diasHastaInicio

        HStack(spacing: 14) {
            Text(oculto ? "🎁" : escapada.icono)
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(oculto ? "Plan sorpresa" : escapada.titulo)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(oculto ? "🔒 \(escapada.pistaSorpresa.isEmpty ? "Destino secreto" : escapada.pistaSorpresa)" : escapada.destino)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Chip(texto: escapada.haEmpezado ? "En curso" : (dias == 0 ? "¡Hoy!" : "En \(dias)d"))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
