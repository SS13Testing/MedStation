GLOBAL_LIST_EMPTY(supply_drop_points)

/// Where ordered supply crates arrive.
/obj/effect/landmark/supply_drop
	name = "supply drop"

/obj/effect/landmark/supply_drop/Initialize(mapload)
	. = ..()
	GLOB.supply_drop_points += src

/obj/effect/landmark/supply_drop/Destroy()
	GLOB.supply_drop_points -= src
	return ..()

/// Something the hospital can order with the medical budget. Make a subtype and give it a name, a cost and contents.
/datum/hospital_supply
	var/name
	var/cost = 100
	/// Typepaths, a number after one means "this many"
	var/list/contents_list = list()
	/// Services take effect at once instead of arriving as a crate
	var/immediate = FALSE

/// What a service does when it is bought (immediate supplies only).
/datum/hospital_supply/proc/fulfil(datum/controller/subsystem/patient_director/director)
	return

/datum/hospital_supply/first_aid
	name = "First aid kits (x3)"
	cost = 120
	contents_list = list(/obj/item/storage/medkit/regular = 3)

/datum/hospital_supply/trauma_kits
	name = "Brute and burn kits (x2 each)"
	cost = 200
	contents_list = list(/obj/item/storage/medkit/brute = 2, /obj/item/storage/medkit/fire = 2)

/datum/hospital_supply/dressings
	name = "Sutures, mesh, gauze and bone gel"
	cost = 150
	contents_list = list(/obj/item/stack/medical/suture = 2, /obj/item/stack/medical/mesh = 2, /obj/item/stack/medical/gauze = 2, /obj/item/stack/medical/bone_gel = 2)

/datum/hospital_supply/surgical_set
	name = "Surgical tool set"
	cost = 250
	contents_list = list(/obj/item/storage/medkit/surgery = 1, /obj/item/bonesetter = 1, /obj/item/blood_filter = 1, /obj/item/surgical_drapes = 1)

/datum/hospital_supply/blood
	name = "Blood bags (assorted, x8)"
	cost = 200
	contents_list = list(
		/obj/item/reagent_containers/blood/o_minus = 3, /obj/item/reagent_containers/blood/o_plus = 2,
		/obj/item/reagent_containers/blood/a_plus = 1, /obj/item/reagent_containers/blood/b_plus = 1,
		/obj/item/reagent_containers/blood/a_minus = 1,
	)

/datum/hospital_supply/emergency_drugs
	name = "Emergency drugs (pill bottles)"
	cost = 220
	contents_list = list(
		/obj/item/storage/pill_bottle/epinephrine = 1, /obj/item/storage/pill_bottle/multiver = 1,
		/obj/item/storage/pill_bottle/mannitol = 1, /obj/item/storage/pill_bottle/penacid = 1,
		/obj/item/storage/pill_bottle/potassiodide = 1, /obj/item/storage/pill_bottle/neurine = 1,
	)

/datum/hospital_supply/defibs
	name = "Defibrillators (x2)"
	cost = 300
	contents_list = list(/obj/item/defibrillator/loaded = 2)

/datum/hospital_supply/analyzer
	name = "Advanced health analyzer"
	cost = 250
	contents_list = list(/obj/item/healthanalyzer/advanced = 1)

/datum/hospital_supply/organs
	name = "Donor organs (liver, heart, lungs, stomach, eyes)"
	cost = 400
	contents_list = list(
		/obj/item/organ/internal/liver = 1, /obj/item/organ/internal/heart = 1, /obj/item/organ/internal/lungs = 1,
		/obj/item/organ/internal/stomach = 1, /obj/item/organ/internal/eyes = 1,
	)

/datum/hospital_supply/triage_taggers
	name = "Triage taggers (x3)"
	cost = 60
	contents_list = list(/obj/item/triage_tagger = 3)

/datum/hospital_supply/stretchers
	name = "Emergency stretchers (x2)"
	cost = 80
	contents_list = list(/obj/item/emergency_bed = 2)

/datum/hospital_supply/refill_medical
	name = "NanoMed Plus refill (tools and dressings)"
	cost = 250
	contents_list = list(/obj/item/vending_refill/medical = 1)

/datum/hospital_supply/refill_drugs
	name = "NanoDrug Plus refill (medicines)"
	cost = 250
	contents_list = list(/obj/item/vending_refill/drugs = 1)

/datum/hospital_supply/refill_wallmed
	name = "Wall-mounted NanoMed refill"
	cost = 150
	contents_list = list(/obj/item/vending_refill/wallmed = 1)

/// Spend money to attract patients: a rush hour for ten minutes. More patients means more cures, more reputation and more money.
/datum/hospital_supply/marketing
	name = "Marketing campaign (rush hour for 10 minutes)"
	cost = 600
	immediate = TRUE

/datum/hospital_supply/marketing/fulfil(datum/controller/subsystem/patient_director/director)
	director.rush_until = world.time + 10 MINUTES
	director.dispatch("The marketing campaign is on: expect more patients for the next ten minutes.")

/datum/hospital_supply/body_bags
	name = "Body bags"
	cost = 40
	contents_list = list(/obj/item/storage/box/bodybags = 1)

/// Every supply, by name.
GLOBAL_LIST_INIT(hospital_supplies, init_hospital_supplies())

/proc/init_hospital_supplies()
	. = list()
	for(var/supply_type in subtypesof(/datum/hospital_supply))
		var/datum/hospital_supply/supply = new supply_type()
		if(supply.name)
			.[supply.name] = supply

/**
 * The hospital terminal: shows how the hospital is doing and spends the medical budget on supplies.
 * Orders arrive as a crate at the supply drop landmark in the ambulance bay.
 */
/obj/machinery/computer/hospital_terminal
	name = "hospital terminal"
	desc = "Shows how the hospital is doing and orders supplies with the medical budget."
	icon_screen = "crew"
	icon_keyboard = "med_key"
	light_color = LIGHT_COLOR_BLUE
	/// Seconds before an order shows up
	var/delivery_delay = 20 SECONDS

/obj/machinery/computer/hospital_terminal/ui_interact(mob/user, datum/tgui/ui)
	var/choice = tgui_input_list(user, "What would you like to do?", name, list("Hospital status", "Case library", "Order supplies"))
	if(!choice || !user.can_perform_action(src, NEED_DEXTERITY | ALLOW_SILICON_REACH))
		return
	switch(choice)
		if("Hospital status")
			to_chat(user, SSpatient_director.get_status_text())
		if("Case library")
			to_chat(user, boxed_message(SSpatient_director.get_library_text()))
		if("Order supplies")
			order_supplies(user)

/obj/machinery/computer/hospital_terminal/proc/order_supplies(mob/user)
	var/datum/bank_account/department/medical = SSeconomy.get_dep_account(ACCOUNT_MED)
	if(!medical)
		to_chat(user, span_warning("The medical budget account can't be reached."))
		return
	var/list/choices = list()
	for(var/supply_name in GLOB.hospital_supplies)
		var/datum/hospital_supply/supply = GLOB.hospital_supplies[supply_name]
		choices["[supply.name] ([supply.cost] cr)"] = supply
	var/choice = tgui_input_list(user, "Medical budget: [medical.account_balance] credits.", "Order supplies", choices)
	var/datum/hospital_supply/wanted = choices[choice]
	if(!wanted || !user.can_perform_action(src, NEED_DEXTERITY | ALLOW_SILICON_REACH))
		return
	if(medical.account_balance < wanted.cost)
		to_chat(user, span_warning("The medical budget can't cover that: [wanted.cost] credits needed, [medical.account_balance] available."))
		playsound(src, 'sound/machines/buzz-sigh.ogg', 40, FALSE)
		return
	medical.adjust_money(-wanted.cost, "Hospital terminal order: [wanted.name]")
	playsound(src, 'sound/machines/ping.ogg', 40, FALSE)
	if(wanted.immediate)
		to_chat(user, span_notice("Done: [wanted.name]."))
		wanted.fulfil(SSpatient_director)
		return
	to_chat(user, span_notice("Ordered: [wanted.name]. It will arrive in the ambulance bay shortly."))
	addtimer(CALLBACK(src, PROC_REF(deliver), wanted), delivery_delay)

/obj/machinery/computer/hospital_terminal/proc/deliver(datum/hospital_supply/supply)
	var/obj/effect/landmark/supply_drop/drop = length(GLOB.supply_drop_points) ? pick(GLOB.supply_drop_points) : null
	var/turf/where = drop ? get_turf(drop) : get_turf(src)
	var/obj/structure/closet/crate/medical/crate = new(where)
	crate.name = "supply crate: [supply.name]"
	for(var/item_type in supply.contents_list)
		for(var/i in 1 to supply.contents_list[item_type])
			new item_type(crate)
	playsound(where, 'sound/machines/chime.ogg', 50, FALSE)
	crate.visible_message(span_notice("A supply crate arrives."))
	SSpatient_director.dispatch("Supply order delivered to the ambulance bay: [supply.name].")
