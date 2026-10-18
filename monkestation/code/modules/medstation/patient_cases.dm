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
	/// 1 = minor, 2 = serious, 3 = critical. Drives the deadline, the payout and the score.
	var/difficulty = 1
	/// Relative chance to be picked
	var/weight = 10
	/// Needs at least this many medical staff on the station to be picked
	var/min_staff = 0
	/// Lines the patient says out loud while they wait
	var/list/symptoms = list("Ow...")
	/// Lines for the intake chart
	var/list/history = list()
	/// Set on cases that can spread so the director/staff know to isolate them
	var/infectious = FALSE
	/// Ways this patient can turn up: by ambulance (on a stretcher) and/or walking into the waiting room
	var/list/arrival_modes = list(PATIENT_ARRIVE_AMBULANCE, PATIENT_ARRIVE_WALKIN)

/// Inflicts the ailment on a freshly created patient.
/datum/patient_case/proc/apply(mob/living/carbon/human/patient)
	return

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
	difficulty = 2
	symptoms = list("My leg... I can't move it!", "I think something's broken.", "It hurts to breathe, doc.")
	history = list("Found at the bottom of a stairwell on the transit ring.", "Conscious, in significant pain.")

/datum/patient_case/blunt_trauma/apply(mob/living/carbon/human/patient)
	for(var/i in 1 to rand(1, 2))
		var/obj/item/bodypart/limb = random_limb(patient)
		if(!limb)
			continue
		limb.receive_damage(brute = rand(15, 25), wound_bonus = CANT_WOUND)
		patient.cause_wound_of_type_and_severity(WOUND_BLUNT, limb, WOUND_SEVERITY_MODERATE, WOUND_SEVERITY_SEVERE)

/datum/patient_case/blunt_trauma/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient)

/datum/patient_case/laceration
	name = "Deep laceration"
	diagnosis = "Arterial laceration, ongoing bleeding"
	difficulty = 2
	symptoms = list("It won't stop bleeding!", "I feel dizzy...", "Please, I'm losing a lot of blood.")
	history = list("Cut on a piece of machinery.", "Bleeding through a field dressing.")

/datum/patient_case/laceration/apply(mob/living/carbon/human/patient)
	var/obj/item/bodypart/limb = random_limb(patient)
	if(!limb)
		return
	limb.receive_damage(brute = rand(15, 25), wound_bonus = CANT_WOUND)
	patient.cause_wound_of_type_and_severity(WOUND_SLASH, limb, WOUND_SEVERITY_SEVERE, WOUND_SEVERITY_CRITICAL)

/datum/patient_case/laceration/is_resolved(mob/living/carbon/human/patient)
	return is_generally_stable(patient)

/datum/patient_case/burns
	name = "Burn injury"
	diagnosis = "Second and third degree burns"
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
	name = "Yellowing skin, confusion"
	diagnosis = "Acute liver failure"
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
	name = "Weight loss, abdominal pain"
	diagnosis = "Parasitic liver infection (needs the liver removed and replaced)"
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
