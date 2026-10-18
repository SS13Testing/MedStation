/**
 * The ambulance shuttle and its console. The ambulance docks in the hospital's ambulance bay; when a call is answered a scene
 * is loaded and the crew drive out to it, treat the patients and bring them back. See field_scenes.dm for the scenes.
 */
/area/shuttle/ambulance
	name = "Ambulance"

/datum/map_template/shuttle/ambulance
	port_id = "ambulance"
	who_can_purchase = null

/datum/map_template/shuttle/ambulance/medstation
	suffix = "medstation"
	name = "hospital ambulance"
	description = "A small ambulance with two stretchers, a pilot seat and room for three more crew."

/// Where the ambulance lives: a 7x5 block in the ambulance bay with the airlock on the top edge.
/obj/docking_port/stationary/ambulance_home
	name = "Hospital ambulance bay"
	shuttle_id = "ambulance_home"
	roundstart_template = /datum/map_template/shuttle/ambulance/medstation
	dir = SOUTH
	width = 7
	dwidth = 3
	height = 5

/// The console in the ambulance: drive to the scene of the call that was answered, or back to the hospital.
/obj/machinery/computer/ambulance_shuttle
	name = "ambulance console"
	desc = "Drives the ambulance out to the scene of a call and back to the hospital."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	light_color = LIGHT_COLOR_BLUE

/obj/machinery/computer/ambulance_shuttle/ui_interact(mob/user, datum/tgui/ui)
	var/obj/docking_port/mobile/ambulance = SSshuttle.getShuttle("ambulance")
	if(!ambulance)
		to_chat(user, span_warning("The ambulance's navigation is offline."))
		return
	if(ambulance.mode != SHUTTLE_IDLE)
		to_chat(user, span_notice("The ambulance is on the road. [ambulance.getStatusText()]"))
		return
	var/obj/docking_port/stationary/scene_dock = SSpatient_director.get_scene_dock()
	var/obj/docking_port/stationary/at = ambulance.get_docked()
	var/list/choices = list()
	if(scene_dock && at != scene_dock)
		choices["Drive to the scene"] = scene_dock.shuttle_id
	if(at != SSshuttle.getDock("ambulance_home"))
		choices["Return to the hospital"] = "ambulance_home"
	if(!length(choices))
		to_chat(user, span_notice("There is nowhere to go: no call is being answered. Answer one from a dispatch console."))
		return
	var/choice = tgui_input_list(user, "Where to?", "Ambulance console", choices)
	if(!choice || !user.can_perform_action(src, NEED_DEXTERITY | ALLOW_SILICON_REACH))
		return
	if(ambulance.mode != SHUTTLE_IDLE)
		return
	var/result = SSshuttle.moveShuttle("ambulance", choices[choice], TRUE)
	if(result != DOCKING_SUCCESS)
		to_chat(user, span_warning("The ambulance can't make that trip right now."))
		return
	to_chat(user, span_notice("The ambulance pulls away."))
