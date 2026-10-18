/// The welcome text new staff get, and the Hospital Guide verb.
/proc/hospital_guide_text()
	return "<span class='notice'><b>Welcome to the hospital.</b><br>\
		Patients arrive two ways: <b>ambulances</b> pull into the ambulance bay (south-west) and unload patients on stretchers \
		(with a paramedic on duty they come as <b>calls</b>: answer one from the dispatch console in the bay or the lounge, then board the <b>ambulance</b> \
		in the bay and use its console to drive out to the scene; treat the patients there, bring them back on the stretchers and drive home. \
		The sooner the better: unanswered calls cost reputation, and anyone left at the scene is lost), \
		and <b>walk-ins</b> come through the waiting room door (west) and sit down. Walk-ins who wait too long leave, and that costs reputation.<br><br>\
		<b>Every patient holds an intake chart</b> with notes from the crew and any known allergies. It does not give the diagnosis: \
		scan them with a health analyzer. Untreated patients get worse once their time runs out, unless they are on a <b>stasis bed</b>. \
		Be careful with medicine: some patients are allergic, and the chart does not always say so (epinephrine treats anaphylaxis).<br><br>\
		<b>Triage</b>: use a triage tagger (triage desk) to tag patients green (minor), yellow (serious) or red (critical). \
		A correct tag earns a bonus when they are discharged.<br>\
		<b>Money</b>: cured patients pay the medical budget. Spend it at a <b>hospital terminal</b> (triage, staff lounge) on tools, blood, drugs and spare organs. \
		Orders arrive as a crate in the ambulance bay.<br>\
		<b>Rating</b>: cures raise the hospital's reputation, deaths lower it faster. A better hospital gets a bigger caseload and rarer, harder patients.<br><br>\
		Use the <b>Hospital Status</b> verb (IC tab) to see how things stand, or <b>Hospital Guide</b> to read this again. \
		When you are done for the day, call the shuttle: it docks at the departure lounge (south-east).</span>"

/mob/living/carbon/human/verb/hospital_guide()
	set name = "Hospital Guide"
	set category = "IC"
	to_chat(src, boxed_message(hospital_guide_text()))

/// Sends the guide to anyone who spawns into a medical job (and the overflow role) a few seconds after they spawn.
/datum/controller/subsystem/patient_director/proc/on_job_spawn(datum/source, datum/job/job, mob/living/spawned, client/player_client)
	SIGNAL_HANDLER
	if(!player_client)
		return
	addtimer(CALLBACK(src, PROC_REF(send_guide), WEAKREF(spawned)), 6 SECONDS)

/datum/controller/subsystem/patient_director/proc/send_guide(datum/weakref/spawned_ref)
	var/mob/living/spawned = spawned_ref?.resolve()
	if(!QDELETED(spawned))
		to_chat(spawned, boxed_message(hospital_guide_text()))
