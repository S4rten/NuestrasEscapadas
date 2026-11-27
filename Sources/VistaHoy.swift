import SwiftUI

// ============================================================================
// MODO "HOY", "CÓMO LLEGAR" Y VOTOS
//  · Almacen.eventos(de:dia:)  -> línea del tiempo de un día (Plan, Hoy e Inicio)
//  · SeccionAhora              -> lo siguiente que toca hoy (pestaña Plan)
//  · TarjetaHoy                -> resumen del día en curso (pantalla Próximas)
//  · BotonesVoto               -> 👍 / 👎 de cada uno en las ideas
// ============================================================================

/// Abre Apple Maps con la ruta desde donde estés hasta `destino`.
func urlRuta(destino: String) -> URL? {
    let limpio = destino.recortado
    guard !limpio.isEmpty else { return nil }
    var comps = URLComponents(string: "https://maps.apple.com/")
    comps?.queryItems = [URLQueryItem(name: "daddr", value: limpio)]
    return comps?.url
}

extension Escapada {
    /// Día del viaje que es hoy (nil si hoy no estáis de viaje).
    var diaDeHoy: Int? { diaDelViaje(para: Date()) }
}

extension Almacen {
    /// Todo lo que pasa un día del viaje, ordenado por hora (lo que no tiene hora va al final).
    func eventos(de escapada: Escapada, dia: Int) -> [EventoLinea] {
        let calendario = Calendar.current
        let fecha = escapada.fechaParaDia(dia)
        var lista: [EventoLinea] = []

        // El día del vuelo se cuenta en la hora local de su aeropuerto.
        for v in vuelosDe(escapada.id) where v.saleElDia(fecha) {
            var detalles = [v.aerolinea, v.numeroVuelo, v.terminalPuerta].filter { !$0.isEmpty }
            if !v.zonaSalida.isEmpty && v.zonaSalida != TimeZone.current.identifier {
                detalles.append("sale \(v.horaSalidaLocal) hora local")
            }
            if let estado = ServicioEstadoVuelos.compartido.resumen(de: v) {
                detalles.insert(estado, at: 0)
            }
            lista.append(EventoLinea(
                id: "vuelo-\(v.id)",
                hora: v.fechaHoraSalida,
                titulo: "\(v.origen) → \(v.destino)",
                subtitulo: detalles.joined(separator: " · "),
                icono: "✈️",
                actividadId: nil,
                completada: false,
                enlace: urlDesdeTexto(v.urlReserva)
            ))
        }

        for t in trenesDe(escapada.id) where calendario.isDate(t.fechaHoraSalida, inSameDayAs: fecha) {
            lista.append(EventoLinea(
                id: "tren-\(t.id)",
                hora: t.fechaHoraSalida,
                titulo: "\(t.estacionOrigen) → \(t.estacionDestino)",
                subtitulo: "\(t.operadora) · \(t.trayecto)",
                icono: "🚂",
                actividadId: nil,
                completada: false,
                enlace: urlDesdeTexto(t.urlReserva),
                ruta: urlRuta(destino: "Estación \(t.estacionOrigen)")
            ))
        }

        for a in alojamientosDe(escapada.id) {
            let nombreAloj = a.nombre.isEmpty ? "Alojamiento" : a.nombre
            let destinoRuta = a.direccion.isEmpty
                ? (a.nombre.isEmpty ? "" : "\(a.nombre), \(escapada.destino)")
                : a.direccion
            if calendario.isDate(a.entrada, inSameDayAs: fecha) {
                lista.append(EventoLinea(
                    id: "entrada-\(a.id)",
                    hora: a.entrada,
                    titulo: "Check-in: \(nombreAloj)",
                    subtitulo: a.direccion,
                    icono: "🔑",
                    actividadId: nil,
                    completada: false,
                    enlace: urlDesdeTexto(a.urlReserva),
                    ruta: urlRuta(destino: destinoRuta)
                ))
            }
            if calendario.isDate(a.salida, inSameDayAs: fecha) {
                lista.append(EventoLinea(
                    id: "salida-\(a.id)",
                    hora: a.salida,
                    titulo: "Check-out: \(nombreAloj)",
                    subtitulo: a.direccion,
                    icono: "🧳",
                    actividadId: nil,
                    completada: false,
                    enlace: urlDesdeTexto(a.urlReserva)
                ))
            }
        }

        for actividad in actividadesDe(escapada.id) where actividad.dia == dia {
            lista.append(EventoLinea(
                id: "actividad-\(actividad.id)",
                hora: actividad.todoElDia ? nil : actividad.hora,
                titulo: actividad.nombreSitio,
                subtitulo: actividad.todoElDia ? "Ocupa todo el día" : (actividad.hora == nil ? "Sin hora fija" : "Plan del día"),
                icono: actividad.todoElDia ? "🌞" : "📍",
                actividadId: actividad.id,
                completada: actividad.completada,
                enlace: urlDesdeTexto(actividad.urlSitio),
                ruta: urlRuta(destino: "\(actividad.nombreSitio), \(escapada.destino)"),
                todoElDia: actividad.todoElDia
            ))
        }

        // Los planes de todo el día van siempre arriba; el resto, por hora.
        return lista.sorted { a, b in
            if a.todoElDia != b.todoElDia { return a.todoElDia }
            switch (a.hora, b.hora) {
            case let (x?, y?):
                return x < y
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.titulo < b.titulo
            }
        }
    }

    /// Lo que queda por hacer hoy: primero lo que tiene hora (desde hace 30 min), luego lo que no.
    func pendientesDeHoy(de escapada: Escapada) -> [EventoLinea] {
        guard let dia = escapada.diaDeHoy else { return [] }
        let limite = Date().addingTimeInterval(-30 * 60)
        return eventos(de: escapada, dia: dia).filter { evento in
            guard !evento.completada else { return false }
            if let hora = evento.hora { return hora >= limite }
            return true
        }
    }
}

// ============================================================================
// "AHORA" en la pestaña Plan (solo el día de hoy)
// ============================================================================

struct SeccionAhora: View {
    @EnvironmentObject var almacen: Almacen
    @ObservedObject private var estadosVuelos = ServicioEstadoVuelos.compartido
    let escapada: Escapada

    var body: some View {
        if let dia = escapada.diaDeHoy {
            let pendientes = almacen.pendientesDeHoy(de: escapada)

            Section {
                if let siguiente = pendientes.first {
                    FilaEventoCompacta(evento: siguiente, destacado: true)
                    if pendientes.count > 1 {
                        FilaEventoCompacta(evento: pendientes[1], destacado: false)
                    }
                } else {
                    Text("No queda nada planeado para hoy. ¡A improvisar! ✨")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Hoy · Día \(dia) de \(escapada.totalDias)")
            }
            .task(id: escapada.id) {
                for v in almacen.vuelosDe(escapada.id) where ServicioEstadoVuelos.esDeHoy(v) {
                    await estadosVuelos.actualizar(v, clave: almacen.claveVuelos)
                }
            }
        }
    }
}

struct FilaEventoCompacta: View {
    let evento: EventoLinea
    let destacado: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(evento.icono)
                .font(destacado ? .title2 : .body)
            VStack(alignment: .leading, spacing: 2) {
                Text(destacado ? "AHORA / LO SIGUIENTE" : "DESPUÉS")
                    .font(.caption2.bold())
                    .foregroundStyle(destacado ? Color.accentColor : Color.secondary)
                Text(evento.titulo)
                    .font(destacado ? .subheadline.bold() : .subheadline)
                Text(evento.todoElDia ? "Todo el día" : (evento.hora.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Sin hora fija"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let ruta = evento.ruta {
                BotonEnlace(titulo: "Ir", url: ruta, icono: "map.fill")
            }
        }
    }
}

// ============================================================================
// TARJETA "HOY" en la pantalla Próximas (cuando hay un viaje en curso)
// ============================================================================

struct TarjetaHoy: View {
    @EnvironmentObject var almacen: Almacen
    @ObservedObject private var tiempo = ServicioTiempo.compartido
    @ObservedObject private var estadosVuelos = ServicioEstadoVuelos.compartido
    let escapada: Escapada

    var body: some View {
        let dia = escapada.diaDeHoy ?? 1
        let pendientes = Array(almacen.pendientesDeHoy(de: escapada).prefix(3))

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Chip(texto: "HOY · DÍA \(dia) DE \(escapada.totalDias)", color: .green)
                Spacer()
                if let lat = escapada.latitud, let lon = escapada.longitud,
                   let p = tiempo.prevision(lat: lat, lon: lon, fecha: Date()) {
                    Text("\(p.emoji) \(p.textoTemperaturas)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(escapada.icono) \(escapada.titulo)")
                .font(.headline)
                .foregroundStyle(.primary)

            if pendientes.isEmpty {
                Text("Nada más planeado para hoy. ¡Disfrutad! ✨")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(pendientes) { e in
                        HStack(spacing: 8) {
                            Text(e.todoElDia ? "Día" : (e.hora.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 48, alignment: .leading)
                            Text("\(e.icono) \(e.titulo)")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Text("Toca para abrir el plan de hoy")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
        )
        .task(id: escapada.id) {
            if let lat = escapada.latitud, let lon = escapada.longitud {
                await tiempo.cargar(lat: lat, lon: lon)
            }
            // Vuelos de hoy: retrasos y puerta (como mucho una consulta por hora).
            for v in almacen.vuelosDe(escapada.id) where ServicioEstadoVuelos.esDeHoy(v) {
                await estadosVuelos.actualizar(v, clave: almacen.claveVuelos)
            }
        }
    }
}

// ============================================================================
// VOTOS 👍 / 👎 (cada uno vota lo suyo; se guarda por campo y no se pisan)
// ============================================================================

struct BotonesVoto: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    let coleccion: Coleccion
    let id: String
    let votos: [String: Int]

    var body: some View {
        let mio = votos[sesion.miId] ?? 0
        let aFavor = votos.values.filter { $0 > 0 }.count
        let enContra = votos.values.filter { $0 < 0 }.count
        let gustaALosDos = almacen.miembros.count >= 2 && almacen.miembros.allSatisfy { votos[$0.id] == 1 }

        HStack(spacing: 6) {
            Button {
                almacen.votar(id, en: coleccion, miId: sesion.miId, valor: mio == 1 ? nil : 1)
            } label: {
                Label("\(aFavor)", systemImage: mio == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.caption2.bold())
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(mio == 1 ? Color.green : Color.gray)

            Button {
                almacen.votar(id, en: coleccion, miId: sesion.miId, valor: mio == -1 ? nil : -1)
            } label: {
                Label("\(enContra)", systemImage: mio == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.caption2.bold())
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(mio == -1 ? Color.red : Color.gray)

            if gustaALosDos {
                Chip(texto: "❤️ Os gusta a los dos", color: .pink)
            }
        }
    }
}
