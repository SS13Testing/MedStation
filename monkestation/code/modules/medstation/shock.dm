/**
 * Pain and shock. Badly hurt or bleeding patients slide into shock each director tick: they go pale and clammy, then collapse
 * and start to suffocate. Lying them down, painkillers, saline, epinephrine, blood and stasis all slow or reverse it.
 * The director calls tick_shock() on the patient each time it processes their record.
 */
/datum/component/shock
	/// 0 (fine) to SHOCK_MAX
	var/level = 0

/datum/component/shock/Initialize()
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/shock/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(parent, COMSIG_LIVING_HEALTHSCAN, PROC_REF(on_healthscan))

/datum/component/shock/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EXAMINE, COMSIG_LIVING_HEALTHSCAN))

/// Heart rate in beats per minute: climbs with injury and shock, zero when dead.
/datum/component/shock/proc/get_pulse(mob/living/carbon/human/patient)
	if(patient.stat == DEAD)
		return 0
	return round(clamp(70 + 60 * get_load(patient) + 0.5 * level, 40, 190))

/// Blood pressure as "systolic/diastolic": drops with blood loss and shock.
/datum/component/shock/proc/get_blood_pressure(mob/living/carbon/human/patient)
	if(patient.stat == DEAD)
		return "0/0"
	var/systolic = round(clamp(120 * patient.blood_volume / BLOOD_VOLUME_NORMAL - 0.4 * level, 20, 140))
	return "[systolic]/[round(systolic * 0.65)]"

/// Health analyzers show vitals; the advanced one also names the shock stage.
/datum/component/shock/proc/on_healthscan(mob/living/source, list/render_list, advanced, mob/user, mode, tochat)
	SIGNAL_HANDLER
	var/mob/living/carbon/human/patient = parent
	var/stage = "stable"
	if(level >= SHOCK_COLLAPSE)
		stage = "DEEP SHOCK"
	else if(level >= SHOCK_PALE)
		stage = "early shock"
	var/style = level >= SHOCK_PALE ? "alert" : "info"
	var/line = "Pulse: [get_pulse(patient)] bpm, blood pressure [get_blood_pressure(patient)]."
	if(advanced)
		line += " Circulation: [stage] ([round(level)]%)."
	render_list += "<span class='[style] ml-1'>[line]</span><br>"

/datum/component/shock/proc/on_examine(atom/source, mob/user, list/examine_list)
	SIGNAL_HANDLER
	if(level >= SHOCK_COLLAPSE)
		examine_list += span_danger("[source.p_Theyre()] in deep shock: grey, clammy and barely responding.")
	else if(level >= SHOCK_PALE)
		examine_list += span_warning("[source.p_Theyre()] pale and clammy, with a racing pulse. [source.p_They()] may be going into shock.")

/// How much pain/injury load the patient is under, 0 to 1+ (fraction of max health lost to brute and burn).
/datum/component/shock/proc/get_load(mob/living/carbon/human/patient)
	return (patient.getBruteLoss() + patient.getFireLoss()) / max(1, patient.maxHealth)

/// One director tick. Returns the new level.
/datum/component/shock/proc/tick_shock(mob/living/carbon/human/patient)
	if(HAS_TRAIT(patient, TRAIT_STASIS))
		return level // frozen in time
	var/load = get_load(patient)
	var/bleeding = patient.blood_volume < BLOOD_VOLUME_OKAY
	var/painkiller = FALSE
	var/stabilised = FALSE
	for(var/datum/reagent/reagent as anything in patient.reagents?.reagent_list)
		if(istype(reagent, /datum/reagent/medicine/painkiller))
			painkiller = TRUE
		else if(istype(reagent, /datum/reagent/medicine/epinephrine) || istype(reagent, /datum/reagent/medicine/salglu_solution))
			stabilised = TRUE
	if(load >= 0.5 || bleeding)
		var/rise = 2 + 4 * load + (patient.blood_volume < BLOOD_VOLUME_BAD ? 4 : 0)
		if(patient.body_position == LYING_DOWN)
			rise *= 0.5
		if(painkiller)
			rise *= 0.5
		level += rise
	else
		level -= 3
	if(stabilised)
		level -= 4
	level = clamp(level, 0, SHOCK_MAX)
	if(level >= SHOCK_COLLAPSE)
		if(patient.stat == CONSCIOUS)
			patient.visible_message(span_danger("[patient] goes grey and collapses!"))
		patient.Unconscious(10 SECONDS)
		patient.adjustOxyLoss(2 + 2 * (level >= SHOCK_MAX), forced = TRUE)
	else if(level >= SHOCK_PALE && patient.stat == CONSCIOUS && prob(30))
		to_chat(patient, span_userdanger("You feel cold, faint and sick."))
	return level

/// The patient's shock level, 0 if they have never been in shock.
/proc/get_shock_level(mob/living/carbon/human/patient)
	var/datum/component/shock/shock = patient.GetComponent(/datum/component/shock)
	return shock ? shock.level : 0
