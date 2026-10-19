/**
 * Careers: persistent medical XP and ranks.
 *
 * Everybody starts as a Trainee (Nurse or Basic EMT) and earns XP by helping to treat patients. XP is kept per player in
 * data/medstation/careers/<ckey>.json, so it survives rounds and restarts. The rank decides which jobs you can take and
 * which tools, medicines and machines you may use on patients (career_locks.dm), and the patient director only sends cases
 * the staff on duty are qualified to treat.
 *
 * Set MEDSTATION_CAREER_LOCKS 0 in config to turn all of this off (everyone is treated as a Chief).
 */

/// Rank names and the XP needed for each. The index is the rank number (0 = Trainee).
GLOBAL_LIST_INIT(career_ranks, list(
	list("Trainee", 0),
	list("Qualified", 300),
	list("Senior", 1000),
	list("Chief", 2500),
))

/// The rank needed to take a job, by job title. Jobs not listed need no rank.
GLOBAL_LIST_INIT(career_job_ranks, list(
	JOB_NURSE = 0,
	JOB_BASIC_EMT = 0,
	JOB_PARAMEDIC = 1,
	JOB_MEDICAL_DOCTOR = 1,
	JOB_CHEMIST = 1,
	JOB_PSYCHOLOGIST = 1,
	JOB_VIROLOGIST = 2,
	JOB_GENETICIST = 2,
	JOB_CHIEF_MEDICAL_OFFICER = 3,
))

/// XP for curing a patient is difficulty times this
#define CAREER_XP_PER_DIFFICULTY 40
/// Ambulance and field patients are worth this much more
#define CAREER_EMERGENCY_XP_MULTIPLIER 1.25
/// Bonus XP for a correct triage tag, and for keeping a contagious patient in the isolation lab
#define CAREER_XP_TRIAGE_BONUS 10
#define CAREER_XP_QUARANTINE_BONUS 10
/// A patient that was lost is still worth this much per difficulty to the people who tried
#define CAREER_XP_PER_DIFFICULTY_LOST 10
/// You have to have worked on a patient at least this many times (items used on them) to share the XP for them
#define CAREER_MIN_CONTRIBUTIONS 2

SUBSYSTEM_DEF(careers)
	name = "Medical Careers"
	flags = SS_NO_FIRE
	/// Where the career files live
	var/career_dir = "data/medstation/careers"
	/// Careers loaded so far, by ckey: list("xp" = number)
	var/list/cache = list()
	/// Testing only: mob -> the rank to treat it as having
	var/list/rank_override = list()

/datum/controller/subsystem/careers/Initialize()
	return SS_INIT_SUCCESS

/// Are ranks and locks switched on? (Off: everybody counts as a Chief.)
/datum/controller/subsystem/careers/proc/locks_enabled()
	return !!CONFIG_GET(number/medstation_career_locks)

// ------------------------------------------------------------------ the data

/datum/controller/subsystem/careers/proc/career_path(ckey)
	return "[career_dir]/[ckey(ckey)].json"

/// The career record for a ckey (loaded from disk the first time), or null for an empty ckey.
/datum/controller/subsystem/careers/proc/get_career(ckey)
	ckey = ckey(ckey)
	if(!ckey)
		return null
	var/list/data = cache[ckey]
	if(!data)
		data = load_career(ckey)
		cache[ckey] = data
	return data

/datum/controller/subsystem/careers/proc/load_career(ckey)
	var/list/data = list("xp" = 0)
	var/path = career_path(ckey)
	if(fexists(path))
		var/list/loaded = safe_json_decode(rustg_file_read(path))
		if(islist(loaded))
			data["xp"] = max(0, round(text2num(loaded["xp"]) || 0))
	return data

/datum/controller/subsystem/careers/proc/save_career(ckey)
	ckey = ckey(ckey)
	var/list/data = cache[ckey]
	if(!data)
		return
	rustg_file_write(json_encode(data), career_path(ckey))

/datum/controller/subsystem/careers/proc/get_xp(ckey)
	var/list/data = get_career(ckey)
	return data ? data["xp"] : 0

/// The rank number (0-3) for an amount of XP.
/datum/controller/subsystem/careers/proc/rank_for_xp(xp)
	. = 0
	for(var/rank in 1 to length(GLOB.career_ranks))
		if(xp >= GLOB.career_ranks[rank][2])
			. = rank - 1

/datum/controller/subsystem/careers/proc/rank_name(rank)
	return GLOB.career_ranks[clamp(rank, 0, length(GLOB.career_ranks) - 1) + 1][1]

/// A player's rank by ckey. (With locks off everyone is a Chief.)
/datum/controller/subsystem/careers/proc/rank_of_ckey(ckey)
	if(!locks_enabled())
		return length(GLOB.career_ranks) - 1
	return rank_for_xp(get_xp(ckey))

/// A mob's rank. Mobs that aren't being played (patients, test dummies, drones) are unrestricted.
/datum/controller/subsystem/careers/proc/rank_of_mob(mob/user)
	if(!locks_enabled())
		return length(GLOB.career_ranks) - 1
	if(user in rank_override)
		return rank_override[user]
	var/ckey = user?.ckey
	if(!ckey)
		return length(GLOB.career_ranks) - 1
	return rank_for_xp(get_xp(ckey))

/// Adds (or removes) XP, saves it and tells the player if they are online. Returns the new total.
/datum/controller/subsystem/careers/proc/add_xp(ckey, amount, reason)
	var/list/data = get_career(ckey)
	if(!data || !amount)
		return 0
	var/old_rank = rank_for_xp(data["xp"])
	data["xp"] = max(0, data["xp"] + round(amount))
	save_career(ckey)
	var/new_rank = rank_for_xp(data["xp"])
	var/client/online = GLOB.directory[ckey(ckey)]
	if(online?.mob)
		if(amount > 0)
			to_chat(online.mob, span_notice("<b>+[round(amount)] career XP</b>[reason ? " ([reason])" : ""]. [xp_progress_text(data["xp"])]"))
		if(new_rank > old_rank)
			to_chat(online.mob, boxed_message(span_greenannounce("<b>PROMOTED to [rank_name(new_rank)]!</b><br>[unlocks_text(new_rank)]")))
	return data["xp"]

/// Sets the XP outright (admins).
/datum/controller/subsystem/careers/proc/set_xp(ckey, amount)
	var/list/data = get_career(ckey)
	if(!data)
		return
	data["xp"] = max(0, round(amount))
	save_career(ckey)

// ------------------------------------------------------------------ jobs

/// The rank a job needs (0 if it isn't listed).
/datum/controller/subsystem/careers/proc/job_rank_required(title)
	return GLOB.career_job_ranks[title] || 0

/// Can this player take this job? (Used by the job subsystem.)
/datum/controller/subsystem/careers/proc/can_take_job(client/player, datum/job/job)
	return can_ckey_take_job(player?.ckey, job.title)

/datum/controller/subsystem/careers/proc/can_ckey_take_job(ckey, title)
	if(!locks_enabled())
		return TRUE
	return rank_of_ckey(ckey) >= job_rank_required(title)

// ------------------------------------------------------------------ text

/// Jobs that open up at a rank.
/datum/controller/subsystem/careers/proc/jobs_at_rank(rank)
	var/list/jobs = list()
	for(var/title in GLOB.career_job_ranks)
		if(GLOB.career_job_ranks[title] == rank)
			jobs += title
	return jobs

/datum/controller/subsystem/careers/proc/unlocks_text(rank)
	var/list/jobs = jobs_at_rank(rank)
	var/list/lines = list()
	if(length(jobs))
		lines += "Jobs you can now take: [english_list(jobs)]."
	if(rank > 0)
		lines += "More tools, medicines and machines are now yours to use on patients."
	return lines.Join(" ")

/datum/controller/subsystem/careers/proc/xp_progress_text(xp)
	var/rank = rank_for_xp(xp)
	if(rank >= length(GLOB.career_ranks) - 1)
		return "[xp] XP, top rank ([rank_name(rank)])."
	var/next_xp = GLOB.career_ranks[rank + 2][2]
	return "[xp] XP, rank [rank_name(rank)]. [next_xp - xp] more for [rank_name(rank + 1)]."

/// What the Career verb and the welcome message show.
/datum/controller/subsystem/careers/proc/career_summary(ckey)
	if(!locks_enabled())
		return "<b>Career ranks are switched off on this server.</b> Everyone may do everything."
	var/xp = get_xp(ckey)
	var/rank = rank_for_xp(xp)
	var/list/lines = list("<b>Your medical career</b>", "Rank: <b>[rank_name(rank)]</b> ([xp_progress_text(xp)])")
	var/list/available = list()
	for(var/title in GLOB.career_job_ranks)
		if(GLOB.career_job_ranks[title] <= rank)
			available += title
	lines += "Jobs you can take: [english_list(available)]."
	if(rank < length(GLOB.career_ranks) - 1)
		lines += "Next rank, [rank_name(rank + 1)]: [unlocks_text(rank + 1)]"
	lines += "Earn XP by helping to treat patients: curing them pays most, and ambulance and field patients pay extra. You have to work on a patient yourself to share the XP."
	return lines.Join("<br>")

// ------------------------------------------------------------------ rewards

/// Pays out XP to everybody who worked on a patient when their stay ends.
/datum/controller/subsystem/careers/proc/reward_record(datum/patient_record/record, outcome)
	var/datum/patient_case/case = record.case
	var/base
	var/reason
	switch(outcome)
		if(PATIENT_OUTCOME_TREATED)
			base = case.difficulty * CAREER_XP_PER_DIFFICULTY
			if(record.arrival_mode != PATIENT_ARRIVE_WALKIN)
				base *= CAREER_EMERGENCY_XP_MULTIPLIER
			if(record.tag_level == case.difficulty)
				base += CAREER_XP_TRIAGE_BONUS
			if(case.infectious && record.isolated)
				base += CAREER_XP_QUARANTINE_BONUS
			reason = "cured [record.patient_name]"
		if(PATIENT_OUTCOME_DIED, PATIENT_OUTCOME_ABANDONED)
			base = case.difficulty * CAREER_XP_PER_DIFFICULTY_LOST
			reason = "you did what you could for [record.patient_name]"
		else
			return
	base = round(base)
	for(var/ckey in record.contributors)
		if(record.contributors[ckey] >= CAREER_MIN_CONTRIBUTIONS)
			add_xp(ckey, base, reason)

// ------------------------------------------------------------------ player and admin interface

/mob/living/carbon/human/verb/career()
	set name = "Career"
	set category = "IC"
	to_chat(src, boxed_message(SScareers.career_summary(ckey)))

ADMIN_VERB(set_career_xp, R_ADMIN|R_FUN, FALSE, "Set Career XP", "Set a player's medical career XP (this also saves it).", ADMIN_CATEGORY_FUN)
	var/target = ckey(tgui_input_text(user, "Whose career? (ckey)", "Set Career XP"))
	if(!target)
		return
	var/current = SScareers.get_xp(target)
	var/amount = tgui_input_number(user, "[target] has [current] XP ([SScareers.rank_name(SScareers.rank_for_xp(current))]). Set it to:", "Set Career XP", current, 100000, 0)
	if(isnull(amount))
		return
	SScareers.set_xp(target, amount)
	message_admins("[key_name_admin(user)] set [target]'s career XP to [amount] ([SScareers.rank_name(SScareers.rank_for_xp(amount))]).")
