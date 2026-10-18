/// How a patient reaches the hospital
#define PATIENT_ARRIVE_AMBULANCE "ambulance"
#define PATIENT_ARRIVE_WALKIN "walk-in"
/// Found at the scene of a call, out in the field
#define PATIENT_ARRIVE_FIELD "field"

/// How a patient's stay ended
#define PATIENT_OUTCOME_TREATED "treated"
#define PATIENT_OUTCOME_DIED "died"
#define PATIENT_OUTCOME_LEFT "left without being seen"
#define PATIENT_OUTCOME_ABANDONED "left behind at the scene"

/// Triage colours: the number matches the difficulty of the case it should be tied to, 0 is black (beyond help).
#define TRIAGE_BLACK 0
#define TRIAGE_GREEN 1
#define TRIAGE_YELLOW 2
#define TRIAGE_RED 3
