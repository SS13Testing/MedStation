/**
 * Ambulance calls. When a paramedic is on duty the ambulance no longer just turns up: a call comes in and somebody has to
 * answer it from the dispatch console. The patients' clocks start when the call comes in, so a slow answer or a long drive
 * means they arrive already worse off. Calls nobody answers in time cost reputation.
 */
/datum/ambulance_call
	/// Where the patients are, for flavour
	var/location
	/// Case types of the patients waiting there
	var/list/case_types = list()
	var/posted_at
	/// Nobody answered by this time: the call is lost
	var/expires_at
	/// How long the ambulance is away fetching them
	var/travel_time

/datum/ambulance_call/New(location, list/case_types, wait_time, travel_time)
	src.location = location
	src.case_types = case_types
	src.travel_time = travel_time
	posted_at = world.time
	expires_at = world.time + wait_time

/// The worst patient on the call (1-3).
/datum/ambulance_call/proc/urgency()
	. = 1
	for(var/case_type in case_types)
		var/datum/patient_case/case = case_type
		. = max(., initial(case.difficulty))

/datum/ambulance_call/proc/urgency_label()
	switch(urgency())
		if(1)
			return "minor"
		if(2)
			return "serious"
	return "CRITICAL"

/datum/ambulance_call/proc/label()
	var/seconds_left = max(0, round((expires_at - world.time) / (1 SECONDS)))
	return "[location]: [length(case_types)] patient[length(case_types) > 1 ? "s" : ""], [urgency_label()] ([seconds_left]s left, [round(travel_time / (1 SECONDS))]s away)"

/// The console that sends the ambulance out.
/obj/machinery/computer/ambulance_dispatch
	name = "ambulance dispatch console"
	desc = "Shows the ambulance calls waiting and sends the ambulance out to one of them."
	icon_screen = "comm"
	icon_keyboard = "tech_key"
	light_color = LIGHT_COLOR_BLUE

/obj/machinery/computer/ambulance_dispatch/ui_interact(mob/user, datum/tgui/ui)
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	if(!length(director.pending_calls))
		to_chat(user, span_notice("No ambulance calls are waiting. [director.ambulance_status()]"))
		return
	var/list/choices = list()
	for(var/datum/ambulance_call/emergency as anything in director.pending_calls)
		choices[emergency.label()] = emergency
	var/choice = tgui_input_list(user, "[director.ambulance_status()]", "Answer which call?", choices)
	var/datum/ambulance_call/chosen = choices[choice]
	if(!chosen || !user.can_perform_action(src, NEED_DEXTERITY | ALLOW_SILICON_REACH))
		return
	if(!director.dispatch_call(chosen, user))
		to_chat(user, span_warning("The ambulance can't go right now: [director.ambulance_status()]"))
