/**
 * Career locks: which tools, medicines and machines need which rank. Rank 0 is a Trainee (Nurse / Basic EMT), 1 Qualified
 * (Doctor / Paramedic), 2 Senior, 3 Chief. Anything not listed is open to everybody.
 *
 * Items and medicines are only locked when they are used on a living patient (an empty hand-off, putting a scalpel in a box or
 * pouring water is fine). The most specific registered type wins, so a CMO's hypospray can be locked higher than a normal one.
 */

/// Tools: the rank needed to use them on a patient.
GLOBAL_LIST_INIT(career_item_locks, list(
	/obj/item/scalpel = 1,
	/obj/item/hemostat = 1,
	/obj/item/retractor = 1,
	/obj/item/cautery = 1,
	/obj/item/bonesetter = 1,
	/obj/item/surgical_drapes = 1,
	/obj/item/circular_saw = 2,
	/obj/item/surgicaldrill = 2,
	/obj/item/blood_filter = 2,
	/obj/item/hypospray = 1,
	/obj/item/hypospray/cmo = 3,
	/obj/item/healthanalyzer/advanced = 1,
	/obj/item/healthanalyzer/range = 2,
))

/// Machines: the rank needed to operate them.
GLOBAL_LIST_INIT(career_machine_locks, list(
	/obj/machinery/chem_dispenser = 1,
	/obj/machinery/chem_master = 1,
	/obj/machinery/chem_heater = 1,
	/obj/machinery/chem_mass_spec = 2,
	/obj/machinery/computer/operating = 1,
	/obj/machinery/sleeper = 1,
	/obj/machinery/computer/pandemic = 2,
	/obj/machinery/rnd/production/techfab/department/medical = 2,
))

/// Medicines: the rank needed to give them to a patient (by what is in the syringe, pill, patch or bottle).
/// Unlisted medicines need rank 1, unlisted toxins rank 3, everything else (water, sugar) none.
GLOBAL_LIST_INIT(career_reagent_locks, list(
	/datum/reagent/medicine/c2/libital = 0,
	/datum/reagent/medicine/c2/aiuri = 0,
	/datum/reagent/medicine/antipathogenic/spaceacillin = 0,
	/datum/reagent/medicine/salglu_solution = 0,
	/datum/reagent/medicine/epinephrine = 1,
	/datum/reagent/medicine/c2/multiver = 1,
	/datum/reagent/medicine/c2/convermol = 1,
	/datum/reagent/medicine/salbutamol = 1,
	/datum/reagent/medicine/oculine = 1,
	/datum/reagent/medicine/mannitol = 2,
	/datum/reagent/medicine/neurine = 2,
))

/// The rank a registry asks for a type (the most specific match), or `default` if nothing matches.
/proc/career_lock_for_type(type, list/registry, default = 0)
	var/best_length = 0
	. = default
	for(var/registered in registry)
		if(ispath(type, registered) && length("[registered]") > best_length)
			best_length = length("[registered]")
			. = registry[registered]

/// The rank needed to give a medicine.
/proc/career_rank_for_reagent(reagent_type)
	// -1 means "not listed" (a null default would be replaced by the proc's own default of 0)
	var/explicit = career_lock_for_type(reagent_type, GLOB.career_reagent_locks, -1)
	if(explicit >= 0)
		return explicit
	if(ispath(reagent_type, /datum/reagent/medicine))
		return 1
	if(ispath(reagent_type, /datum/reagent/toxin))
		return 3
	return 0

/// The rank needed to use something (an item type, machine type or reagent type): what the treatability test checks.
/proc/career_rank_for_type(type)
	if(ispath(type, /datum/reagent))
		return career_rank_for_reagent(type)
	if(ispath(type, /obj/machinery))
		return career_lock_for_type(type, GLOB.career_machine_locks)
	return career_lock_for_type(type, GLOB.career_item_locks)

/// The rank needed to use this item on this target: tools by type, containers by what is in them.
/datum/controller/subsystem/careers/proc/rank_needed_for_item(obj/item/item, atom/target)
	var/needed = career_lock_for_type(item.type, GLOB.career_item_locks)
	if(istype(item, /obj/item/reagent_containers) && item.reagents && isliving(target))
		for(var/datum/reagent/reagent as anything in item.reagents.reagent_list)
			needed = max(needed, career_rank_for_reagent(reagent.type))
	return needed

/// May this user use this item on this target? Tells them why not. (Hooked into the attack chain.)
/datum/controller/subsystem/careers/proc/may_use_item(mob/user, obj/item/item, atom/target)
	if(!isliving(target) || !locks_enabled())
		return TRUE
	var/needed = rank_needed_for_item(item, target)
	if(!needed)
		return TRUE
	var/rank = rank_of_mob(user)
	if(rank >= needed)
		return TRUE
	to_chat(user, span_warning("You haven't been trained to use [item] on patients yet: it needs the [rank_name(needed)] rank (you are [rank_name(rank)]). Treat patients to earn career XP."))
	return FALSE

/// May this user operate this machine? Tells them why not. (Hooked into machine interaction.)
/datum/controller/subsystem/careers/proc/may_operate(mob/user, obj/machinery/machine)
	if(!locks_enabled())
		return TRUE
	var/needed = career_lock_for_type(machine.type, GLOB.career_machine_locks)
	if(!needed)
		return TRUE
	var/rank = rank_of_mob(user)
	if(rank >= needed)
		return TRUE
	to_chat(user, span_warning("You haven't been trained to operate [machine] yet: it needs the [rank_name(needed)] rank (you are [rank_name(rank)]). Treat patients to earn career XP."))
	return FALSE
