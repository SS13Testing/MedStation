/**
 * The entry-level jobs of the career ladder: Nurse (the hospital side) and Basic EMT (the ambulance side). Anyone can take
 * them, there are always slots, and they are the overflow role. The better jobs need a rank (see GLOB.career_job_ranks).
 */
/datum/id_trim/job/medical_doctor/nurse
	assignment = "Nurse"

/datum/id_trim/job/paramedic/basic_emt
	assignment = "Basic EMT"

/datum/job/nurse
	title = JOB_NURSE
	description = "Look after patients under the doctors' direction: dressings, scans, stasis beds, triage, decontamination. \
		Learn the ropes and earn career XP to rise through the ranks."
	department_head = list(JOB_CHIEF_MEDICAL_OFFICER)
	faction = FACTION_STATION
	total_positions = -1
	spawn_positions = -1
	supervisors = SUPERVISOR_CMO
	exp_granted_type = EXP_TYPE_CREW
	config_tag = "NURSE"

	outfit = /datum/outfit/job/nurse

	paycheck = PAYCHECK_CREW
	paycheck_department = ACCOUNT_MED

	liver_traits = list(TRAIT_MEDICAL_METABOLISM)

	display_order = JOB_DISPLAY_ORDER_NURSE
	departments_list = list(
		/datum/job_department/medical,
		)
	rpg_title = "Acolyte"
	job_flags = STATION_JOB_FLAGS

/datum/outfit/job/nurse
	name = "Nurse"
	jobtype = /datum/job/nurse

	id = /obj/item/card/id/advanced
	id_trim = /datum/id_trim/job/medical_doctor/nurse
	uniform = /obj/item/clothing/under/rank/medical/scrubs/blue
	suit = /obj/item/clothing/suit/toggle/labcoat
	head = /obj/item/clothing/head/utility/surgerycap
	ears = /obj/item/radio/headset/headset_med
	gloves = /obj/item/clothing/gloves/latex
	shoes = /obj/item/clothing/shoes/sneakers/white
	l_pocket = /obj/item/modular_computer/pda/medical
	l_hand = /obj/item/storage/medkit/regular

	backpack = /obj/item/storage/backpack/medic
	satchel = /obj/item/storage/backpack/satchel/med
	duffelbag = /obj/item/storage/backpack/duffelbag/med
	backpack_contents = list(
		/obj/item/healthanalyzer = 1,
		/obj/item/clothing/neck/stethoscope = 1,
		/obj/item/stack/medical/gauze = 1,
		)

/datum/job/basic_emt
	title = JOB_BASIC_EMT
	description = "Crew the ambulance: answer calls, stabilise people at the scene and bring them back to the hospital. \
		Learn the ropes and earn career XP to become a Paramedic."
	department_head = list(JOB_CHIEF_MEDICAL_OFFICER)
	faction = FACTION_STATION
	total_positions = -1
	spawn_positions = -1
	supervisors = SUPERVISOR_CMO
	exp_granted_type = EXP_TYPE_CREW
	config_tag = "BASIC_EMT"

	outfit = /datum/outfit/job/basic_emt

	paycheck = PAYCHECK_CREW
	paycheck_department = ACCOUNT_MED

	liver_traits = list(TRAIT_MEDICAL_METABOLISM)

	display_order = JOB_DISPLAY_ORDER_BASIC_EMT
	departments_list = list(
		/datum/job_department/medical,
		)
	rpg_title = "Corpse Runner's Apprentice"
	job_flags = STATION_JOB_FLAGS

/datum/outfit/job/basic_emt
	name = "Basic EMT"
	jobtype = /datum/job/basic_emt

	id = /obj/item/card/id/advanced
	id_trim = /datum/id_trim/job/paramedic/basic_emt
	uniform = /obj/item/clothing/under/rank/medical/paramedic
	suit = /obj/item/clothing/suit/toggle/labcoat/paramedic
	head = /obj/item/clothing/head/soft/paramedic
	belt = /obj/item/storage/belt/medical
	ears = /obj/item/radio/headset/headset_med
	gloves = /obj/item/clothing/gloves/latex
	shoes = /obj/item/clothing/shoes/workboots/black
	l_pocket = /obj/item/modular_computer/pda/medical
	r_pocket = /obj/item/gps/medical
	l_hand = /obj/item/storage/medkit/regular

	backpack = /obj/item/storage/backpack/medic
	satchel = /obj/item/storage/backpack/satchel/med
	duffelbag = /obj/item/storage/backpack/duffelbag/med
	backpack_contents = list(
		/obj/item/emergency_bed = 1,
		/obj/item/healthanalyzer = 1,
		/obj/item/stack/medical/gauze = 1,
		)

/obj/effect/landmark/start/nurse
	name = JOB_NURSE
	icon_state = "Medical Doctor"

/obj/effect/landmark/start/basic_emt
	name = JOB_BASIC_EMT
	icon_state = "Paramedic"
