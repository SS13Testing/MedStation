/**
 * Wound infection. Patients with open wounds (lacerations, shrapnel, penetrating wounds) who are left waiting past their
 * deadline can get their wounds infected: they run a fever, take toxin damage and can't be discharged until a course of
 * antibiotics (spaceacillin) has cleared it. Stasis stops it from starting.
 */
/datum/component/wound_infection

/datum/component/wound_infection/Initialize()
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/wound_infection/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(parent, COMSIG_LIVING_HEALTHSCAN, PROC_REF(on_healthscan))

/datum/component/wound_infection/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EXAMINE, COMSIG_LIVING_HEALTHSCAN))

/datum/component/wound_infection/proc/on_examine(atom/source, mob/user, list/examine_list)
	SIGNAL_HANDLER
	examine_list += span_warning("[source.p_Their()] wounds are red, swollen and weeping. They look infected.")

/datum/component/wound_infection/proc/on_healthscan(mob/living/source, list/render_list, advanced, mob/user, mode, tochat)
	SIGNAL_HANDLER
	render_list += "<span class='alert ml-1'>[advanced ? "Wound infection detected: bacterial, treat with antibiotics (spaceacillin)." : "Subject has a fever and infected wounds."]</span><br>"

/// One director tick. Antibiotics clear it; otherwise it poisons the patient.
/datum/component/wound_infection/proc/tick_infection(mob/living/carbon/human/patient)
	if(patient.reagents?.has_reagent(/datum/reagent/medicine/antipathogenic/spaceacillin))
		to_chat(patient, span_notice("The fever breaks and your wounds stop throbbing."))
		qdel(src)
		return FALSE
	patient.adjustToxLoss(0.5, forced = TRUE)
	if(patient.stat == CONSCIOUS && prob(20))
		to_chat(patient, span_warning("Your wounds throb and you feel feverish."))
	return TRUE

/// Is this patient's wound infected?
/proc/is_infected(mob/living/carbon/human/patient)
	return !!patient.GetComponent(/datum/component/wound_infection)
