import SwiftUI

// ============================================================================
// FICHA DEL PAÍS (pestaña Lista): enchufes, emergencias, por qué lado se
// conduce, propinas y documentación para viajar desde España.
// Va dentro de la app, así que funciona sin conexión.
// La moneda no sale aquí: ya está en cada gasto.
// ============================================================================

struct InfoPais {
    let enchufes: [String]          // tipos de enchufe (C, F, G…)
    let voltios: Int
    let emergencias: String
    let conduceIzquierda: Bool
    let propina: String
    let documentos: String          // para españoles
    var extra: String = ""

    /// En España se usan C y F: con estos tipos no hace falta adaptador.
    var necesitaAdaptador: Bool {
        !enchufes.contains { ["C", "E", "F"].contains($0) }
    }
}

enum FichasPaises {
    private static let schengen = "DNI o pasaporte en vigor. Sin visado."
    private static let ue = "DNI o pasaporte en vigor. Sin visado."

    static let datos: [String: InfoPais] = [
        // Europa
        "FR": InfoPais(enchufes: ["C", "E"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "El servicio va incluido; se suele redondear o dejar 1–2 €.", documentos: ue),
        "IT": InfoPais(enchufes: ["C", "F", "L"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "No es obligatoria; ojo al «coperto» (cubierto) que ya viene en la cuenta.", documentos: ue, extra: "Algunas ciudades cobran tasa turística en el hotel."),
        "PT": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Opcional; un 5–10 % si os han tratado bien.", documentos: ue),
        "DE": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Se redondea o se deja un 5–10 % al pagar (se dice el total al camarero).", documentos: ue),
        "GB": InfoPais(enchufes: ["G"], voltios: 230, emergencias: "999 (o 112)", conduceIzquierda: true, propina: "10–12,5 % si no viene ya como «service charge».", documentos: "Pasaporte (el DNI no vale) y autorización ETA solicitada antes del viaje."),
        "IE": InfoPais(enchufes: ["G"], voltios: 230, emergencias: "112 o 999", conduceIzquierda: true, propina: "Un 10 % en restaurantes si no está incluido.", documentos: ue),
        "NL": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Se redondea; un 5–10 % en restaurantes.", documentos: ue),
        "BE": InfoPais(enchufes: ["C", "E"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "El servicio va incluido; redondear es suficiente.", documentos: ue),
        "LU": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Incluida; se redondea.", documentos: ue),
        "CH": InfoPais(enchufes: ["C", "J"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Incluida en el precio; se redondea.", documentos: schengen, extra: "Enchufe tipo J: los planos (C) entran, los gordos (F) no."),
        "AT": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Un 5–10 %, redondeando al pagar.", documentos: ue, extra: "Para autopistas hace falta la viñeta (vignette)."),
        "GR": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Un 5–10 % o redondear.", documentos: ue),
        "HR": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Un 10 % en restaurantes.", documentos: ue),
        "CZ": InfoPais(enchufes: ["C", "E"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Un 10 %, redondeando al pagar.", documentos: ue),
        "HU": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "10–15 %; mirad si ya viene como «szervizdíj».", documentos: ue),
        "PL": InfoPais(enchufes: ["C", "E"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Un 10 % en restaurantes.", documentos: ue),
        "DK": InfoPais(enchufes: ["C", "E", "F", "K"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Incluida; no se espera más.", documentos: ue),
        "SE": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Opcional; se redondea.", documentos: ue, extra: "Casi todo se paga con tarjeta."),
        "NO": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Opcional; se redondea.", documentos: schengen, extra: "Casi todo se paga con tarjeta."),
        "FI": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "No se espera.", documentos: ue),
        "IS": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Incluida; no se espera.", documentos: schengen),
        "MT": InfoPais(enchufes: ["G"], voltios: 230, emergencias: "112", conduceIzquierda: true, propina: "Un 5–10 %.", documentos: ue),
        "CY": InfoPais(enchufes: ["G"], voltios: 230, emergencias: "112", conduceIzquierda: true, propina: "Un 10 % si no está incluido.", documentos: ue),
        "AD": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Como en España.", documentos: "DNI o pasaporte en vigor."),
        "TR": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: false, propina: "Un 5–10 % en restaurantes.", documentos: "Pasaporte recomendado (el DNI se suele aceptar). Sin visado hasta 90 días."),

        // África y Oriente Medio
        "MA": InfoPais(enchufes: ["C", "E"], voltios: 220, emergencias: "19 policía · 15 ambulancia", conduceIzquierda: false, propina: "Muy habitual: un 10 % y monedas por pequeños servicios.", documentos: "Pasaporte en vigor. Sin visado hasta 90 días."),
        "EG": InfoPais(enchufes: ["C", "F"], voltios: 220, emergencias: "122 policía · 123 ambulancia", conduceIzquierda: false, propina: "Imprescindible (bakshish) en casi todo: llevad billetes pequeños.", documentos: "Pasaporte (6 meses de validez) y visado (en el aeropuerto o e-Visa)."),
        "AE": InfoPais(enchufes: ["G"], voltios: 230, emergencias: "999", conduceIzquierda: false, propina: "Un 10 % si no está incluido.", documentos: "Pasaporte (6 meses de validez). Sin visado."),

        // América
        "US": InfoPais(enchufes: ["A", "B"], voltios: 120, emergencias: "911", conduceIzquierda: false, propina: "Casi obligatoria: 18–20 % en restaurantes; los precios no llevan impuestos.", documentos: "Pasaporte y ESTA aprobada antes de volar."),
        "CA": InfoPais(enchufes: ["A", "B"], voltios: 120, emergencias: "911", conduceIzquierda: false, propina: "15–20 % en restaurantes.", documentos: "Pasaporte y eTA si llegáis en avión."),
        "MX": InfoPais(enchufes: ["A", "B"], voltios: 127, emergencias: "911", conduceIzquierda: false, propina: "10–15 % en restaurantes.", documentos: "Pasaporte (6 meses de validez). Sin visado."),
        "CU": InfoPais(enchufes: ["A", "B", "C", "L"], voltios: 110, emergencias: "106 policía · 104 ambulancia", conduceIzquierda: false, propina: "Muy agradecida: un 10 %.", documentos: "Pasaporte, visado de turista y formulario D'Viajeros."),
        "DO": InfoPais(enchufes: ["A", "B"], voltios: 120, emergencias: "911", conduceIzquierda: false, propina: "Suele venir un 10 % incluido; se añade algo más.", documentos: "Pasaporte y formulario e-Ticket (entrada y salida)."),
        "CR": InfoPais(enchufes: ["A", "B"], voltios: 120, emergencias: "911", conduceIzquierda: false, propina: "El 10 % suele venir incluido.", documentos: "Pasaporte (con billete de salida). Sin visado."),
        "CO": InfoPais(enchufes: ["A", "B"], voltios: 110, emergencias: "123", conduceIzquierda: false, propina: "Os preguntarán si incluir el 10 % «voluntario».", documentos: "Pasaporte y formulario Check-MIG antes de volar."),
        "PE": InfoPais(enchufes: ["A", "C"], voltios: 220, emergencias: "105 policía · 116 bomberos", conduceIzquierda: false, propina: "Un 10 % en restaurantes.", documentos: "Pasaporte (6 meses de validez). Sin visado."),
        "AR": InfoPais(enchufes: ["C", "I"], voltios: 220, emergencias: "911", conduceIzquierda: false, propina: "Un 10 % en restaurantes.", documentos: "Pasaporte. Sin visado."),
        "BR": InfoPais(enchufes: ["C", "N"], voltios: 220, emergencias: "190 policía · 192 ambulancia", conduceIzquierda: false, propina: "El 10 % suele venir incluido.", documentos: "Pasaporte (6 meses de validez). Sin visado.", extra: "El voltaje cambia según la ciudad (127 o 220 V)."),
        "CL": InfoPais(enchufes: ["C", "L"], voltios: 220, emergencias: "133 policía · 131 ambulancia", conduceIzquierda: false, propina: "Os preguntarán si incluir el 10 %.", documentos: "Pasaporte. Sin visado."),

        // Asia y Oceanía
        "JP": InfoPais(enchufes: ["A", "B"], voltios: 100, emergencias: "110 policía · 119 ambulancia", conduceIzquierda: true, propina: "No se deja: puede resultar hasta incómodo.", documentos: "Pasaporte. Sin visado hasta 90 días.", extra: "Llevad efectivo: hay sitios que no aceptan tarjeta."),
        "KR": InfoPais(enchufes: ["C", "F"], voltios: 220, emergencias: "112 policía · 119 ambulancia", conduceIzquierda: false, propina: "No se deja.", documentos: "Pasaporte; comprobad si toca pedir la K-ETA."),
        "CN": InfoPais(enchufes: ["A", "C", "I"], voltios: 220, emergencias: "110 policía · 120 ambulancia", conduceIzquierda: false, propina: "No se deja.", documentos: "Pasaporte; exención de visado para estancias cortas (comprobad que sigue vigente).", extra: "Google, WhatsApp e Instagram no funcionan sin VPN."),
        "TH": InfoPais(enchufes: ["A", "B", "C", "O"], voltios: 220, emergencias: "191 policía · 1669 ambulancia", conduceIzquierda: true, propina: "Se redondea; un 10 % en sitios turísticos.", documentos: "Pasaporte (6 meses de validez) y tarjeta digital de llegada (TDAC)."),
        "VN": InfoPais(enchufes: ["A", "C"], voltios: 220, emergencias: "113 policía · 115 ambulancia", conduceIzquierda: false, propina: "Opcional; muy agradecida.", documentos: "Pasaporte; sin visado para estancias cortas (si no, e-Visa)."),
        "ID": InfoPais(enchufes: ["C", "F"], voltios: 230, emergencias: "112", conduceIzquierda: true, propina: "Un 5–10 % si no viene el «service».", documentos: "Pasaporte (6 meses de validez) y visado a la llegada o e-VOA.", extra: "Bali cobra una tasa turística al llegar."),
        "SG": InfoPais(enchufes: ["G"], voltios: 230, emergencias: "999 policía · 995 ambulancia", conduceIzquierda: true, propina: "Ya viene un 10 % de servicio.", documentos: "Pasaporte y SG Arrival Card (3 días antes)."),
        "IN": InfoPais(enchufes: ["C", "D", "M"], voltios: 230, emergencias: "112", conduceIzquierda: true, propina: "Un 10 % en restaurantes.", documentos: "Pasaporte y e-Visa antes de volar."),
        "MV": InfoPais(enchufes: ["D", "G"], voltios: 230, emergencias: "119 policía · 102 ambulancia", conduceIzquierda: true, propina: "Suele venir un 10 % incluido.", documentos: "Pasaporte y formulario IMUGA antes de volar."),
        "AU": InfoPais(enchufes: ["I"], voltios: 230, emergencias: "000", conduceIzquierda: true, propina: "No se espera.", documentos: "Pasaporte y eVisitor antes de volar."),
        "NZ": InfoPais(enchufes: ["I"], voltios: 230, emergencias: "111", conduceIzquierda: true, propina: "No se espera.", documentos: "Pasaporte y NZeTA antes de volar.")
    ]
}

/// Sección de la pestaña Lista con la ficha del país de destino.
struct SeccionFichaPais: View {
    let escapada: Escapada
    @State private var abierta = false
    @ObservedObject private var exteriores = ServicioExteriores.compartido
    @State private var vistoActualizacion = ""

    /// Última actualización de Exteriores que ya se ha visto en esta escapada.
    private var claveVisto: String { "escapadas_exteriores_visto_\(escapada.id)" }

    var body: some View {
        let iso = escapada.paisCodigo.uppercased()
        if !iso.isEmpty, iso != "ES" {
            Section {
                DisclosureGroup(isExpanded: $abierta) {
                    BloqueExteriores(iso: iso, escapada: escapada)
                    if let info = FichasPaises.datos[iso] {
                        contenido(info)
                    } else {
                        Text("Aún no tenemos la ficha de este país. Consultad las recomendaciones de viaje de exteriores.gob.es.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(Paises.bandera(iso))
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ficha de \(Paises.nombre(iso))")
                                .font(.subheadline.weight(.semibold))
                            if let info = FichasPaises.datos[iso] {
                                Text(resumen(info))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if let f = exteriores.fichas[iso] {
                                if Exteriores.cambioTrasPlanear(f, escapada: escapada) && f.actualizacion != vistoActualizacion {
                                    Text("🆕 Exteriores ha cambiado sus recomendaciones")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                }
                                if !f.avisos.isEmpty {
                                    Text("⚠️ Hay zonas a las que desaconseja viajar")
                                        .font(.caption.bold())
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            } footer: {
                if abierta {
                    Text("Para viajeros con nacionalidad española. Los requisitos cambian: comprobadlos antes en exteriores.gob.es › Recomendaciones de viaje.")
                }
            }
            .task(id: iso) {
                // Solo para viajes que aún no se han hecho; si lo guardado es reciente, no se vuelve a pedir.
                if !escapada.yaVivida {
                    await exteriores.actualizarSiHaceFalta(iso)
                }
            }
            .onAppear {
                vistoActualizacion = UserDefaults.standard.string(forKey: claveVisto) ?? ""
            }
            .onChange(of: abierta) { _, ahora in
                if ahora { marcarVisto(iso) }
            }
            .onChange(of: exteriores.fichas[iso]?.actualizacion) { _, _ in
                if abierta { marcarVisto(iso) }
            }
        }
    }

    private func marcarVisto(_ iso: String) {
        guard let f = exteriores.fichas[iso] else { return }
        UserDefaults.standard.set(f.actualizacion, forKey: claveVisto)
        vistoActualizacion = f.actualizacion
    }

    private func resumen(_ info: InfoPais) -> String {
        var partes: [String] = []
        partes.append(info.necesitaAdaptador ? "🔌 Necesitáis adaptador" : "🔌 Sin adaptador")
        if info.conduceIzquierda { partes.append("🚗 Por la izquierda") }
        partes.append("🆘 \(info.emergencias)")
        return partes.joined(separator: " · ")
    }

    @ViewBuilder
    private func contenido(_ info: InfoPais) -> some View {
        filaDato("🔌", "Enchufes",
                 "Tipo \(info.enchufes.joined(separator: ", ")) · \(info.voltios) V\n"
                 + (info.necesitaAdaptador
                    ? "Necesitáis adaptador: los enchufes de España no entran."
                    : "Vuestros cargadores entran sin adaptador.")
                 + (info.voltios < 200 ? "\nOjo: con \(info.voltios) V los móviles cargan bien, pero secadores y planchas de pelo españolas no funcionan bien." : ""))
        filaDato("🆘", "Emergencias", info.emergencias)
        filaDato("🚗", "Conducción", info.conduceIzquierda ? "Se conduce por la IZQUIERDA. Mirad primero a la derecha al cruzar." : "Por la derecha, como en España.")
        filaDato("💶", "Propina", info.propina)
        filaDato("🛂", "Documentación", info.documentos)
        if !info.extra.isEmpty {
            filaDato("💡", "A tener en cuenta", info.extra)
        }
    }

    private func filaDato(_ icono: String, _ titulo: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icono)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(texto)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
