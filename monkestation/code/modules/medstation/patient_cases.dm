/**
 * A patient case: one ailment that the patient director can hand to an NPC patient.
 *
 * To add a new case, make a subtype, give it symptoms/history for the intake chart, inflict the ailment in apply()
 * and say when it is cured in is_resolved(). The director does the rest (spawning, deterioration, discharge, score).
 */
/datum/patient_case
	/// Shown to the staff in dispatch messages
	var/name = "Unknown complaint"
	/// What it really is. Only revealed to the staff once the patient is discharged or dies.
	var/diagnosis = "Unknown"
	/// What it takes to treat this case: a list of groups, and one thing from each group must be obtainable (see the
	/// medstation_treatability unit test). Item types, machinery types or reagent types.
	var/list/needs = list()
	/// How to treat it. Shown in the case library once the staff have seen this kind of case.
	var/treatment = "Scan the patient and treat what you find."
	/// 1 = minor, 2 = serious, 3 = critical. Drives the deadline, the payout and the score.
	var/difficulty = 1
	/// Relative chance to be picked
	var/weight = 10
	/// Needs at least this many medical staff on the station to be picked
	var/min_staff = 0
	/// Hospital level needed before this case turns up. 0 = by difficulty (critical cases need a better hospital).
	var/min_level = 0
	/// Career rank (0 Trainee, 1 Qualified, 2 Senior, 3 Chief) the staff need to treat this: the director only sends cases that
	/// somebody on duty is qualified for. The medstation_treatability test checks every need is within this rank.
	var/required_rank = 0
	/// Lines the patient says out loud while they wait
	var/list/symptoms = list("Ow...")
	/// Lines for the intake chart
	var/list/history = list()
	/// Set on cases that can spread so the director/staff know to isolate them
	var/infectious = FALSE
	/// Chemical exposure: the patient arrives contaminated and has to be washed in a shower before they can be discharged
	var/contaminated = FALSE
	/// Ways this patient can turn up: by ambulance (on a stretcher) and/or walking into the waiting room
	var/list/arrival_modes = list(PATIENT_ARRIVE_AMBULANCE, PATIENT_ARRIVE_WALKIN)

/// Hospital level (see patient_director.dm) needed for this case to turn up.
/datum/patient_case/proc/get_min_level()
	return min_level || (difficulty >= 3 ? 2 : 1)

/// Inflicts the ailment on a freshly created patient.
/datum/patient_case/proc/apply(mob/living/carbon/human/patient)
	return

/// Called by the director after apply(): contaminated cases arrive covered in residue.
/datum/patient_case/proc/after_apply(mob/living/carbon/human/patient)
	if(contaminated)
		patient.AddComponent(/datum/component/contaminated)

/// TRUE once the ailment is cured. Must be FALSE straight after apply().
/datum/patient_case/proc/is_resolved(mob/living/carbon/human/patient)
	return FALSE

/// Called every director tick once the patient has waited too long without being put in stasis.
/datum/patient_case/proc/worsen(mob/living/carbon/human/patient)
	patient.adjustOxyLoss(6)

/// Seconds of waiting before the patient starts getting worse, by difficulty.
/datum/patient_case/proc/get_deadline()
	switch(difficulty)
		if(1)
			return 8 MINUTES
		if(2)
			return 5 MINUTES
	return 3 MINUTES

/// How long a walk-in waits in the waiting room before giving up and leaving.
/datum/patient_case/proc/get_patience()
	switch(difficulty)
		if(1)
			return 10 MINUTES
		if(2)
			return 7 MINUTES
	return 5 MINUTES

/// Money (to the medical budget) for a successful discharge.
/datum/patient_case/proc/get_payout()
	return 100 * difficulty

/// Tidy "is this person generally fine" check shared by the injury cases.
/datum/patient_case/proc/is_generally_stable(mob/living/carbon/human/patient, brute_max = 15, burn_max = 15, tox_max = 15, oxy_max = 15)
	return patient.getBruteLoss() <= brute_max \
		&& patient.getFireLoss() <= burn_max \
		&& patient.getToxLoss() <= tox_max \
		&& patient.getOxyLoss() <= oxy_max \
		&& !length(patient.all_wounds)

/// Picks a random limb (arms/legs) of the patient.
/datum/patient_case/proc/random_limb(mob/living/carbon/human/patient)
	return patient.get_bodypart(pick(BODY_ZONE_L_ARM, BODY_ZONE_R_ARM, BODY_ZONE_L_LEG, BODY_ZONE_R_LEG))

// ------------------------------------------------------------------ injuries

/datum/patient_case/blunt_trauma
	name = "Fall / crush injury"
	diagnosis = "Fractures from blunt trauma"
	treatment = "Set the broken bones (bone gel, bonesetter or the fracture-repair surgery), then heal the bruising with brute medicine, sutures or a trauma kit. Gauze slows any bleeding."
	needs = list(list(/obj/item/stack/medical/bone_gel, /obj/item/bonesetter, /obj/item/stack/sticky_tape/surgical), list(/obj/item/stack/medical/suture, /obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/gauze))
	difficulty = 2
	symptoms = list("My leg... I can't move it!", "I think something's broken.", "It hurts to breathe, doc.")
	history = list("Found at the bottom of a stairwell on the transit ring.", "Conscious, in significant pain.")

/datum/patient_case/blunt_trauma/apply(mob/living/carbon/human/patient)
	for(var/i in 1 to rand(1, 2))
		var/obj/item/bodypart/limb = random_limb(patient)
		if(!limb)
			continue
		limb.receive_damage(brute = rand(25, 35), wound_bonus = CANT_WOUND)
		patient.cause_wound_of_type_and_severity(WOUND_BLUNT, limb, WOUND_SEVERITY_MODERATE, WOUND_SEVERITY_SEVERE)

/datum/patient_case/blunt_trauma/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient)

/datum/patient_case/laceration
	name = "Deep laceration"
	diagnosis = "Arterial laceration, ongoing bleeding"
	treatment = "Stop the bleeding first (gauze or sutures). If they have lost a lot of blood, transfuse the right blood type, then heal the brute damage."
	needs = list(list(/obj/item/stack/medical/gauze, /obj/item/stack/medical/suture), list(/obj/item/reagent_containers/blood))
	difficulty = 2
	symptoms = list("It won't stop bleeding!", "I feel dizzy...", "Please, I'm losing a lot of blood.")
	history = list("Cut on a piece of machinery.", "Bleeding through a field dressing.")

/datum/patient_case/laceration/apply(mob/living/carbon/human/patient)
	var/obj/item/bodypart/limb = random_limb(patient)
	if(!limb)
		return
	limb.receive_damage(brute = rand(25, 35), wound_bonus = CANT_WOUND)
	patient.cause_wound_of_type_and_severity(WOUND_SLASH, limb, WOUND_SEVERITY_SEVERE, WOUND_SEVERITY_CRITICAL)

/datum/patient_case/laceration/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient)

/datum/patient_case/burns
	name = "Burn injury"
	diagnosis = "Second and third degree burns"
	treatment = "Mesh or ointment for the burns, burn medicine (aiuri or lenturi) for the rest. Treat the burn wound so it doesn't get infected."
	needs = list(list(/obj/item/stack/medical/mesh, /obj/item/stack/medical/ointment))
	difficulty = 1
	symptoms = list("It burns...", "Please, something for the pain.", "My arm... it's all blistered.")
	history = list("Caught in a small electrical fire.", "Burns to the arms and torso.")

/datum/patient_case/burns/apply(mob/living/carbon/human/patient)
	var/obj/item/bodypart/limb = random_limb(patient)
	patient.adjustFireLoss(rand(40, 60))
	if(limb)
		patient.cause_wound_of_type_and_severity(WOUND_BURN, limb, WOUND_SEVERITY_MODERATE, WOUND_SEVERITY_SEVERE)

/datum/patient_case/burns/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient)

/datum/patient_case/chest_wound
	name = "Penetrating chest wound"
	diagnosis = "Punctured lung from a penetrating chest wound"
	treatment = "Put them on a stasis bed straight away. Repair the puncture wound, give oxygen medicine (salbutamol or convermol) and heal the lung damage; severe lung damage needs surgery."
	required_rank = 2
	needs = list(list(/obj/machinery/stasis), list(/obj/item/stack/medical/suture, /obj/item/stack/medical/gauze), list(/datum/reagent/medicine/salbutamol, /datum/reagent/medicine/c2/convermol), list(/obj/item/scalpel), list(/obj/item/retractor), list(/obj/item/hemostat), list(/obj/item/cautery))
	difficulty = 3
	min_staff = 2
	weight = 6
	arrival_modes = list(PATIENT_ARRIVE_AMBULANCE)
	symptoms = list("I can't... breathe...", "*wheeze*", "It's... my chest...")
	history = list("Impaled on a loose support strut.", "Laboured breathing, reduced chest movement on one side.")

/datum/patient_case/chest_wound/apply(mob/living/carbon/human/patient)
	var/obj/item/bodypart/chest = patient.get_bodypart(BODY_ZONE_CHEST)
	if(chest)
		chest.receive_damage(brute = rand(20, 30), wound_bonus = CANT_WOUND)
		patient.cause_wound_of_type_and_severity(WOUND_PIERCE, chest, WOUND_SEVERITY_SEVERE, WOUND_SEVERITY_CRITICAL)
	patient.adjustOrganLoss(ORGAN_SLOT_LUNGS, 40)
	patient.adjustOxyLoss(30)
	patient.Unconscious(3 MINUTES)

/datum/patient_case/chest_wound/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient) && patient.get_organ_loss(ORGAN_SLOT_LUNGS) <= 30

// ------------------------------------------------------------------ poisoning / organs

/datum/patient_case/poisoning
	name = "Suspected poisoning"
	diagnosis = "Formaldehyde ingestion"
	treatment = "Wash them in a shower first (they are covered in residue and it keeps hurting them). Scan them to see what is in their blood, purge it with multiver, then heal the toxin damage."
	required_rank = 1
	contaminated = TRUE
	needs = list(list(/datum/reagent/medicine/c2/multiver), list(/obj/machinery/shower))
	difficulty = 2
	symptoms = list("I feel sick...", "My stomach is on fire.", "I drank something from the lab fridge...")
	history = list("Mistook a chemical sample for a drink.", "Nauseous, vomiting.")

/datum/patient_case/poisoning/apply(mob/living/carbon/human/patient)
	patient.reagents.add_reagent(/datum/reagent/toxin/formaldehyde, 15)
	patient.adjustToxLoss(35)

/datum/patient_case/poisoning/worsen(mob/living/carbon/human/patient)
	patient.adjustToxLoss(5)

/datum/patient_case/poisoning/is_resolved(mob/living/carbon/human/patient)
	if(!is_generally_stable(patient, tox_max = 10))
		return FALSE
	return !patient.reagents.has_reagent(/datum/reagent/toxin/formaldehyde)

/datum/patient_case/liver_failure
	min_level = 4
	name = "Yellowing skin, confusion"
	diagnosis = "Acute liver failure"
	treatment = "Heal the toxin damage with multiver and either repair the liver or replace it (organ manipulation, donor liver from the terminal)."
	required_rank = 2
	needs = list(list(/datum/reagent/medicine/c2/multiver), list(/obj/item/organ/internal/liver), list(/obj/item/scalpel), list(/obj/item/retractor), list(/obj/item/hemostat), list(/obj/item/cautery))
	difficulty = 3
	min_staff = 2
	weight = 6
	symptoms = list("Everything is... fuzzy.", "I'm so tired.", "Why is my skin this colour?")
	history = list("Several days of worsening fatigue.", "Jaundice, confusion.")

/datum/patient_case/liver_failure/apply(mob/living/carbon/human/patient)
	patient.adjustOrganLoss(ORGAN_SLOT_LIVER, 95)
	patient.adjustToxLoss(25)

/datum/patient_case/liver_failure/worsen(mob/living/carbon/human/patient)
	patient.adjustToxLoss(6)

/datum/patient_case/liver_failure/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient, tox_max = 20) && patient.get_organ_loss(ORGAN_SLOT_LIVER) <= 40

/datum/patient_case/respiratory
	name = "Shortness of breath"
	diagnosis = "Acute respiratory distress"
	treatment = "Wash them in a shower first (they are covered in residue and it keeps hurting them). Give oxygen medicine (salbutamol or convermol), keep their airway clear and heal the lung damage; severe damage needs lung surgery."
	required_rank = 1
	contaminated = TRUE
	needs = list(list(/datum/reagent/medicine/salbutamol, /datum/reagent/medicine/c2/convermol), list(/obj/machinery/shower))
	difficulty = 2
	symptoms = list("I can't catch my breath...", "*cough* *cough*", "Everything's going dark.")
	history = list("Inhaled fumes from a coolant leak.", "Wheezing, lips turning blue.")

/datum/patient_case/respiratory/apply(mob/living/carbon/human/patient)
	patient.adjustOrganLoss(ORGAN_SLOT_LUNGS, 45)
	patient.adjustOxyLoss(45)

/datum/patient_case/respiratory/worsen(mob/living/carbon/human/patient)
	patient.adjustOxyLoss(8)

/datum/patient_case/respiratory/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient) && patient.get_organ_loss(ORGAN_SLOT_LUNGS) <= 25

// ------------------------------------------------------------------ infections

/datum/patient_case/flu
	name = "Fever and cough"
	diagnosis = "Influenza"
	treatment = "Spaceacillin cures it. Keep them out of the wards and away from the other patients (the isolation lab) until they are better."
	needs = list(list(/datum/reagent/medicine/antipathogenic/spaceacillin))
	difficulty = 1
	weight = 14
	infectious = TRUE
	arrival_modes = list(PATIENT_ARRIVE_WALKIN)
	symptoms = list("*cough*", "*sneezes*", "I feel awful.", "I've had a fever since yesterday.")
	history = list("Fever, aches, productive cough.", "Several coworkers off sick this week.")

/datum/patient_case/flu/apply(mob/living/carbon/human/patient)
	patient.ForceContractDisease(new /datum/disease/flu(), make_copy = FALSE)

/datum/patient_case/flu/worsen(mob/living/carbon/human/patient)
	patient.adjustToxLoss(2)

/datum/patient_case/flu/is_resolved(mob/living/carbon/human/patient)
	return !length(patient.diseases) && patient.getToxLoss() <= 15

/datum/patient_case/parasite
	min_level = 4
	name = "Weight loss, abdominal pain"
	diagnosis = "Parasitic liver infection (needs the liver removed and replaced)"
	treatment = "The parasite lives in the liver: remove the liver in surgery, then transplant a new one (donor organs can be ordered at the terminal)."
	required_rank = 2
	needs = list(list(/obj/item/organ/internal/liver), list(/obj/item/scalpel), list(/obj/item/retractor), list(/obj/item/hemostat), list(/obj/item/cautery))
	difficulty = 3
	min_staff = 2
	weight = 5
	arrival_modes = list(PATIENT_ARRIVE_WALKIN)
	symptoms = list("My stomach hurts all the time.", "I keep losing weight.", "Something is wrong inside me.")
	history = list("Weeks of abdominal pain and weight loss.", "Ate at a cheap noodle bar on the transit ring.")

/datum/patient_case/parasite/apply(mob/living/carbon/human/patient)
	patient.ForceContractDisease(new /datum/disease/parasite(), make_copy = FALSE)

/datum/patient_case/parasite/worsen(mob/living/carbon/human/patient)
	patient.adjustToxLoss(3)

/datum/patient_case/parasite/is_resolved(mob/living/carbon/human/patient)
	return !length(patient.diseases) && !!patient.get_organ_slot(ORGAN_SLOT_LIVER) && patient.getToxLoss() <= 15

// ------------------------------------------------------------------ surgical cases

/datum/patient_case/appendicitis
	name = "Severe abdominal pain"
	diagnosis = "Appendicitis (the appendix has to come out)"
	treatment = "Operate: remove the inflamed appendix with organ manipulation surgery. Don't leave it too long, it will burst."
	required_rank = 1
	needs = list(list(/obj/item/scalpel), list(/obj/item/retractor), list(/obj/item/hemostat), list(/obj/item/cautery))
	difficulty = 2
	weight = 9
	symptoms = list("It hurts right here, low on the right...", "I feel sick and I think I have a fever.", "*groans* My stomach...")
	history = list("Pain that started around the navel and moved to the lower right abdomen.", "Nausea, low fever, will not eat.")

/datum/patient_case/appendicitis/apply(mob/living/carbon/human/patient)
	var/obj/item/organ/internal/appendix/appendix = patient.get_organ_slot(ORGAN_SLOT_APPENDIX)
	if(!appendix)
		appendix = new()
		appendix.Insert(patient, special = TRUE)
	appendix.inflamation_stage = 2
	appendix.update_appearance()
	patient.adjustOrganLoss(ORGAN_SLOT_APPENDIX, 20)

/datum/patient_case/appendicitis/worsen(mob/living/carbon/human/patient)
	patient.adjustToxLoss(3)
	var/obj/item/organ/internal/appendix/appendix = patient.get_organ_slot(ORGAN_SLOT_APPENDIX)
	if(appendix)
		appendix.inflamation_stage = 3
		patient.adjustOrganLoss(ORGAN_SLOT_APPENDIX, 8)

/datum/patient_case/appendicitis/is_resolved(mob/living/carbon/human/patient)
	var/obj/item/organ/internal/appendix/appendix = patient.get_organ_slot(ORGAN_SLOT_APPENDIX)
	return (!appendix || !appendix.inflamation_stage) && is_generally_stable(patient, tox_max = 30)

/datum/patient_case/shrapnel
	name = "Debris injury to the chest"
	diagnosis = "Glass shard lodged in the chest cavity (cavity surgery to remove it)"
	treatment = "Cavity surgery to take the foreign body out of the chest, then close the wound and heal the damage."
	required_rank = 2
	needs = list(list(/obj/item/scalpel), list(/obj/item/retractor), list(/obj/item/hemostat), list(/obj/item/cautery), list(/obj/item/circular_saw))
	difficulty = 2
	weight = 7
	arrival_modes = list(PATIENT_ARRIVE_AMBULANCE)
	symptoms = list("Something's inside me, I can feel it moving.", "It hurts when I breathe.", "A window blew out right next to me.")
	history = list("Caught next to a window failure.", "Entry wound on the chest, foreign body suspected.")

/datum/patient_case/shrapnel/apply(mob/living/carbon/human/patient)
	var/obj/item/bodypart/chest/chest = patient.get_bodypart(BODY_ZONE_CHEST)
	if(!chest)
		return
	chest.cavity_item = new /obj/item/shard(patient)
	chest.receive_damage(brute = rand(15, 25), wound_bonus = CANT_WOUND)
	patient.cause_wound_of_type_and_severity(WOUND_PIERCE, chest, WOUND_SEVERITY_MODERATE, WOUND_SEVERITY_SEVERE)

/datum/patient_case/shrapnel/worsen(mob/living/carbon/human/patient)
	patient.adjustBruteLoss(3)

/datum/patient_case/shrapnel/is_resolved(mob/living/carbon/human/patient)
	var/obj/item/bodypart/chest/chest = patient.get_bodypart(BODY_ZONE_CHEST)
	return !chest?.cavity_item && is_generally_stable(patient)

/datum/patient_case/heart_attack
	min_level = 4
	name = "Crushing chest pain"
	diagnosis = "Cardiac arrest"
	treatment = "Defibrillate (CPR while the defib charges), give epinephrine to restart the heart, then treat the oxygen damage. Stasis buys time."
	required_rank = 2
	needs = list(list(/obj/item/defibrillator), list(/datum/reagent/medicine/epinephrine))
	difficulty = 3
	min_staff = 2
	weight = 5
	arrival_modes = list(PATIENT_ARRIVE_AMBULANCE)
	symptoms = list("*gasps* My chest...", "Left arm... numb...", "Tell my family...")
	history = list("Collapsed at the gym. Bystanders did CPR for a few minutes.", "Unresponsive on arrival, no pulse.")

/datum/patient_case/heart_attack/apply(mob/living/carbon/human/patient)
	patient.set_heartattack(TRUE)
	patient.Unconscious(3 MINUTES)

/datum/patient_case/heart_attack/worsen(mob/living/carbon/human/patient)
	patient.adjustOxyLoss(8)

/datum/patient_case/heart_attack/is_resolved(mob/living/carbon/human/patient)
	return !patient.undergoing_cardiac_arrest() && is_generally_stable(patient)

/datum/patient_case/head_injury
	name = "Head trauma"
	diagnosis = "Traumatic brain injury"
	treatment = "Give mannitol for the brain damage and keep them on a stasis bed while unconscious; severe cases need brain surgery."
	required_rank = 2
	needs = list(list(/datum/reagent/medicine/mannitol), list(/obj/machinery/stasis))
	difficulty = 3
	min_staff = 2
	weight = 5
	arrival_modes = list(PATIENT_ARRIVE_AMBULANCE)
	symptoms = list("Where... where am I?", "*mumbles*", "My head is splitting.")
	history = list("Struck on the head by a falling crate.", "Brief loss of consciousness, now confused and drowsy.")

/datum/patient_case/head_injury/apply(mob/living/carbon/human/patient)
	patient.adjustOrganLoss(ORGAN_SLOT_BRAIN, 55)
	patient.Unconscious(2 MINUTES)

/datum/patient_case/head_injury/worsen(mob/living/carbon/human/patient)
	patient.adjustOrganLoss(ORGAN_SLOT_BRAIN, 6)

/datum/patient_case/head_injury/is_resolved(mob/living/carbon/human/patient)
	return patient.get_organ_loss(ORGAN_SLOT_BRAIN) <= 20 && is_generally_stable(patient)

/datum/patient_case/eye_injury
	name = "Eye injury"
	diagnosis = "Chemical damage to the eyes"
	treatment = "Wash them in a shower first (they are covered in residue and it keeps hurting them). Oculine restores the eyes quickly, or do eye surgery for serious damage."
	required_rank = 1
	contaminated = TRUE
	needs = list(list(/datum/reagent/medicine/oculine, /obj/item/scalpel), list(/obj/machinery/shower))
	difficulty = 1
	weight = 8
	arrival_modes = list(PATIENT_ARRIVE_WALKIN)
	symptoms = list("My eyes! They're burning!", "I can barely see.", "Something splashed in my face at work.")
	history = list("Splashed with a cleaning agent.", "Severe redness and watering in both eyes.")

/datum/patient_case/eye_injury/apply(mob/living/carbon/human/patient)
	patient.adjustOrganLoss(ORGAN_SLOT_EYES, 40)

/datum/patient_case/eye_injury/worsen(mob/living/carbon/human/patient)
	patient.adjustOrganLoss(ORGAN_SLOT_EYES, 4)

/datum/patient_case/eye_injury/is_resolved(mob/living/carbon/human/patient)
	return patient.get_organ_loss(ORGAN_SLOT_EYES) <= 10
