/**
 * Bedside vitals monitor: reads pulse, blood pressure, blood level and shock for every patient lying within a few tiles,
 * so the ICU can be watched without scanning each patient by hand.
 */
/obj/machinery/computer/vitals_monitor
	name = "vitals monitor"
	desc = "Shows the pulse, blood pressure and blood level of the patients on the beds nearby."
	icon_screen = "crew"
	icon_keyboard = "med_key"
	light_color = LIGHT_COLOR_BLUE
	/// How far it can read, in tiles
	var/read_range = 4

/obj/machinery/computer/vitals_monitor/ui_interact(mob/user, datum/tgui/ui)
	to_chat(user, boxed_message(get_readout()))

/// Vitals text for every living or dead patient lying in range.
/obj/machinery/computer/vitals_monitor/proc/get_readout()
	var/list/lines = list("<b>VITALS MONITOR</b>")
	var/count = 0
	for(var/mob/living/carbon/human/patient in range(read_range, src))
		if(patient.body_position != LYING_DOWN && !patient.buckled)
			continue
		count++
		var/datum/component/shock/shock = patient.LoadComponent(/datum/component/shock)
		var/state = patient.stat == DEAD ? "<b>NO SIGNAL</b>" : "pulse [shock.get_pulse(patient)] bpm"
		lines += "[patient.real_name]: [state], BP [shock.get_blood_pressure(patient)], blood [round(patient.blood_volume / BLOOD_VOLUME_NORMAL * 100)]%, shock [round(shock.level)]%[HAS_TRAIT(patient, TRAIT_STASIS) ? " (stasis)" : ""]"
	if(!count)
		lines += "No patients on the monitored beds."
	return lines.Join("<br>")
