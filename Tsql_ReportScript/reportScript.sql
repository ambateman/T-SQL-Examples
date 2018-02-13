USE [DamageComplaint]
GO
/****** Object:  StoredProcedure [Reporting].[WDCR260_UnfinishedComplaints]    Script Date: 12/22/2017 4:29:18 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author: Bateman, Tony
-- Create date: 20170721
-- Description: Report needed for tracking older open complaints
-- Complaints broken up into three groups based on special criteria. 
-- I could have broken the subquery out into a special function 
-- and adjusted for the changes, but I just want it work right now.
-- There is a second report parameter, but I used the filtering in the
-- report itself to handle that situation.
-- =============================================
ALTER PROCEDURE [Reporting].[WDCR260_UnfinishedComplaints]

  @District varchar(100)

AS

BEGIN
-- SET NOCOUNT ON added to prevent extra result sets from
-- interfering with SELECT statements.
SET NOCOUNT ON;

IF OBJECT_ID('tempdb..#CleanComplaints') IS NOT NULL DROP TABLE #CleanComplaints
IF OBJECT_ID('tempdb..#UnfinishedSpecies') IS NOT NULL DROP TABLE #UnfinishedSpecies
IF OBJECT_ID('tempdb..#UnfinishedPermit') IS NOT NULL DROP TABLE #UnfinishedPermit
IF OBJECT_ID('tempdb..#UnfinishedTags') IS NOT NULL DROP TABLE #UnfinishedTags

-------------START #CLEANCOMPLAINTS TEMP TABLE CREATION ----------------------
--The purpose of the creation of the #CleanComplaints temp table
--is to filter out complaints with duplicate formNumbers. 
--I don't think it happens often, but it has at least once.

;WITH cte AS
(
SELECT * , ROW_NUMBER() OVER (PARTITION BY FormNumber ORDER BY ReceivedDate ASC) as rn
FROM Complaint c
WHERE c.IsDeleted = '0' AND isdate(c.CompletedDate)='0' AND isNULL(c.SpeciesId,'0') != '0'
)

select * 
into #CleanComplaints  -- This is the filtered version to use as the basis for the report.
from cte WHERE rn=1
ORDER BY Id ASC

---------------END OF CREATION OF #CLEANCOMPLAINTS TEMP TABLE -----------------------------

--------------MODIFY SPECIES TABLE TO HOLD ADDITIONAL INFORMATION -------------------------------
--Now to build a slightly modified species table with complaint type 
--and overdue trigger value added. This saves a lot of code from the original attempt
--at this report. It looks cleaner, too.
SELECT s.Id
,s.Name as Species
, CASE WHEN s.Id in ('6','22') THEN 'Bear/Cougar Complaints' ELSE 'Standard Complaints' END as ComplaintGroup
, CASE WHEN s.Id in ('11','26','34','74','104','106','138') THEN '150' ELSE '30' END as TriggerPoint  -- = Number of days before considered delinquent
into #UnfinishedSpecies
FROM Species s
-- END OF MODIFIED SPECIES TABLE ------------------------------------------------------------

--------------START OF CREATE #UNFINISHEDPERMIT TEMP TABLE ------------------------------------
--The reason for this table is I need to get information about 
--
;WITH cte AS
(
SELECT * , ROW_NUMBER() OVER (PARTITION BY ComplaintID ORDER BY EndDate ASC) AS rn
FROM Permit p
)
select * 
into #UnfinishedPermit  -- This is the filtered version to use when joining to main select.
from cte WHERE rn=1
ORDER BY ComplaintId ASC
--------------END OF CREATION OF #UNFINISHEDPERMIT TEMP TABLE --------------------------------------

--------------START OF CREATE #UNFINISHEDTAG TEMP TABLE --------------------------------------
--The join to the issued hunt and issued hunt hunter tables is another source of duplicate records. 
--The following temp table is filtered to contain only issued hunts with hunters who have unfinished
--tags. Just one hunter in a group is needed to flip this to 'yes'. 
--The idea then is to check to see if any given complaint has at least one entry in the #unfinishedTag table.

;WITH cte as (
SELECT ih.ComplaintId, ihh.Success  
FROM IssuedHunt ih
join IssuedHuntHunter ihh  on ihh.IssuedHuntId = ih.Id
where  ihh.Success = '2'  -- only interested in unfinished (indeterminate)
)
select *, ROW_NUMBER() OVER (PARTITION BY ComplaintID ORDER BY Success ASC) AS rn
into #UnfinishedTags  -- This is the filtered version to use as the basis for the report.
FROM cte 

--------------END OF CREATION OF #UNFINISHEDTAG TEMP TABLE --------------------------------------


----THIS NEXT SELECT IS WHAT GETS RETURNED TO THE REPORT -----------------------------------
select s.Species
, s.ComplaintGroup 
, s.TriggerPoint
, w.Name as WaterShed
, d.Name as District
, a.ADName as recName
, LTRIM(RTRIM(dbo.ProperCase(a.FirstName) + ' ' + dbo.ProperCase(a.LastName))) AS 'Received By'
, LTRIM(RTRIM(dbo.ProperCase(p.FirstName) + ' ' + dbo.ProperCase(p.LastName))) AS 'Land Owner'
, DATEDIFF(d,cc.ReceivedDate, GetDate()) as 'Days Pending'
, CASE WHEN ISDATE(pmt.EndDate) = '1' AND  pmt.EndDate < GETDATE() THEN 'Yes'  ELSE 'No' END AS 'Expired Permit'
, case WHEN EXISTS(SELECT * FROM #UnfinishedTags u WHERE u.ComplaintId = cc.ComplainantId) THEN 'Yes' ELSE 'No' END AS 'Uncompleted Tags'  --Join to this temp table kills report
, cc.*  -- Sorry about all these fields, but I get an error in ssrs when I try to use a subset. This isn't hurting anything.

FROM #CleanComplaints cc
LEFT JOIN #UnfinishedSpecies s on s.id = cc.SpeciesId
LEFT JOIN Watershed w ON w.Id = cc.WatershedId
LEFT JOIN DistrictOffice d on d.Id = cc.DistrictOfficeId
LEFT JOIN ADUser a ON a.Id = cc.ReceivedBy
JOIN Person p on p.Id = cc.ComplainantId
LEFT JOIN #UnfinishedPermit pmt on  pmt.ComplaintId = cc.Id


--Either the maximum elapsed days has gone by, OR a permit has expired for this complaint
WHERE DATEDIFF(d,cc.ReceivedDate, GetDate()) > = s.TriggerPoint OR (ISDATE(pmt.EndDate) = '1' AND  pmt.EndDate < GETDATE())
AND cc.DistrictOfficeId IN (select Value FROM dbo.fnSplit(@District, ','))

END