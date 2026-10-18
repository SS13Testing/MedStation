/// Areas for the MedStation hospital map. They are unpowered-by-design (no APCs or cables needed), so the map
/// only has to place rooms and furniture. Everything is a medical area so existing medical checks keep working.
/area/station/medical/hospital
	name = "Hospital"
	icon_state = "medbay"
	requires_power = FALSE

/area/station/medical/hospital/corridor
	name = "\improper Hospital Corridor"
	icon_state = "med_central"

/area/station/medical/hospital/lobby
	name = "\improper Waiting Room"
	icon_state = "med_lobby"

/area/station/medical/hospital/triage
	name = "\improper Triage"
	icon_state = "exam_room"

/area/station/medical/hospital/emergency_room
	name = "\improper Emergency Room"
	icon_state = "med_central"

/area/station/medical/hospital/ward
	name = "\improper Inpatient Ward"
	icon_state = "patients"

/area/station/medical/hospital/diagnostics
	name = "\improper Diagnostics"
	icon_state = "exam_room"

/area/station/medical/hospital/pharmacy
	name = "\improper Pharmacy"
	icon_state = "pharmacy"

/area/station/medical/hospital/surgery_a
	name = "\improper Operating Theatre A"
	icon_state = "foresurgery"

/area/station/medical/hospital/surgery_b
	name = "\improper Operating Theatre B"
	icon_state = "aftsurgery"

/area/station/medical/hospital/icu
	name = "\improper Intensive Care"
	icon_state = "cryo"

/area/station/medical/hospital/morgue
	name = "\improper Hospital Morgue"
	icon_state = "morgue"

/area/station/medical/hospital/virology
	name = "\improper Isolation Lab"
	icon_state = "virology"

/area/station/medical/hospital/ambulance_bay
	name = "\improper Ambulance Bay"
	icon_state = "med_aft"

/area/station/medical/hospital/lounge
	name = "\improper Staff Lounge"
	icon_state = "med_break"

/area/station/medical/hospital/lockers
	name = "\improper Locker Room"
	icon_state = "med_break"

/area/station/medical/hospital/departures
	name = "\improper Departure Lounge"
	icon_state = "exit"
