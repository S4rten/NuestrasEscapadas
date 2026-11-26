import Foundation
import EventKit

// ============================================================================
// AÑADIR AL CALENDARIO DE iOS: la escapada (todo el viaje) + vuelos, trenes,
// check-in/out y planes con hora. Solo pide permiso para AÑADIR eventos
// (la app no puede leer tu calendario).
// ============================================================================

enum ErrorCalendario: LocalizedError {
    case sinPermiso

    var errorDescription: String? {
        "No hay permiso para añadir eventos. Actívalo en Ajustes de iOS › Escapadas › Calendarios."
    }
}

@MainActor
enum Calendario {
    private static func clave(_ escapadaId: String) -> String { "escapadas_calendario_\(escapadaId)" }

    /// Cuándo se añadió esta escapada al calendario desde este iPhone (para no duplicar).
    static func fechaAnadida(_ escapadaId: String) -> Date? {
        UserDefaults.standard.object(forKey: clave(escapadaId)) as? Date
    }

    /// Añade los eventos y devuelve cuántos se han creado.
    static func anadir(_ escapada: Escapada, almacen: Almacen) async throws -> Int {
        let store = EKEventStore()
        let permitido = try await store.requestWriteOnlyAccessToEvents()
        guard permitido else { throw ErrorCalendario.sinPermiso }
        guard let calendario = store.defaultCalendarForNewEvents else { throw ErrorCalendario.sinPermiso }

        var total = 0
        func crear(_ titulo: String, inicio: Date, fin: Date, todoElDia: Bool = false,
                   lugar: String = "", notas: String = "", alarmaMinutos: Int? = nil) throws {
            let evento = EKEvent(eventStore: store)
            evento.calendar = calendario
            evento.title = titulo
            evento.startDate = inicio
            evento.endDate = max(fin, inicio.addingTimeInterval(todoElDia ? 0 : 15 * 60))
            evento.isAllDay = todoElDia
            if !lugar.isEmpty { evento.location = lugar }
            if !notas.isEmpty { evento.notes = notas }
            if let minutos = alarmaMinutos {
                evento.addAlarm(EKAlarm(relativeOffset: TimeInterval(-minutos * 60)))
            }
            try store.save(evento, span: .thisEvent, commit: false)
            total += 1
        }

        // El viaje entero
        try crear("\(escapada.icono) \(escapada.titulo)",
                  inicio: escapada.fechaInicio.inicioDelDia,
                  fin: escapada.fechaFin.inicioDelDia,
                  todoElDia: true,
                  lugar: escapada.destino,
                  notas: "Añadido desde Nuestras Escapadas")

        for v in almacen.vuelosDe(escapada.id) {
            let detalle = [v.aerolinea, v.numeroVuelo, v.localizador.isEmpty ? "" : "Localizador: \(v.localizador)", v.terminalPuerta]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            try crear("✈️ \(v.origen) → \(v.destino)",
                      inicio: v.fechaHoraSalida, fin: v.fechaHoraLlegada,
                      lugar: v.origen, notas: detalle, alarmaMinutos: 180)
        }

        for t in almacen.trenesDe(escapada.id) {
            try crear("🚂 \(t.estacionOrigen) → \(t.estacionDestino)",
                      inicio: t.fechaHoraSalida, fin: t.fechaHoraLlegada,
                      lugar: t.estacionOrigen,
                      notas: [t.operadora, t.localizador.isEmpty ? "" : "Localizador: \(t.localizador)"]
                        .filter { !$0.isEmpty }.joined(separator: "\n"),
                      alarmaMinutos: 60)
        }

        for h in almacen.alojamientosDe(escapada.id) {
            let nombre = h.nombre.isEmpty ? "Alojamiento" : h.nombre
            let notas = h.codigoReserva.isEmpty ? "" : "Reserva: \(h.codigoReserva)"
            try crear("🔑 Check-in: \(nombre)", inicio: h.entrada, fin: h.entrada.addingTimeInterval(3600),
                      lugar: h.direccion, notas: notas)
            try crear("🧳 Check-out: \(nombre)", inicio: h.salida, fin: h.salida.addingTimeInterval(1800),
                      lugar: h.direccion, notas: notas)
        }

        for a in almacen.actividadesDe(escapada.id) {
            let dia = escapada.fechaParaDia(a.dia)
            if a.todoElDia {
                try crear("🌞 \(a.nombreSitio)", inicio: dia, fin: dia, todoElDia: true,
                          lugar: "\(a.nombreSitio), \(escapada.destino)", notas: a.urlSitio)
            } else if let hora = a.hora {
                try crear("📍 \(a.nombreSitio)", inicio: hora, fin: hora.addingTimeInterval(3600),
                          lugar: "\(a.nombreSitio), \(escapada.destino)", notas: a.urlSitio, alarmaMinutos: 30)
            }
        }

        try store.commit()
        UserDefaults.standard.set(Date(), forKey: clave(escapada.id))
        return total
    }
}
