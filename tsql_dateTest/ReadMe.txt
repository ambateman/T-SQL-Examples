Report Script:

This is a stored procedure designed to be executed by another stored procedure. Its sole purpose is to decide if two date intervals overlap. This may seem like an odd need, but this is to associate multiple future date intervals for any given unique item (in this case, a species ID). Since only the current date is visible, this test acts as a safeguard to clerical error, and makes sure that date intervals have both start and end dates before any new date (open ended or not) is added. Returning any value other than zero indicates that the update or addition is invalid.
