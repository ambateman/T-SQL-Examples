USE [CommercialFisheries]
GO
/****** Object:  StoredProcedure [dbo].[pr_ValidateDateRange]    Script Date: 12/22/2017 4:27:17 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[pr_ValidateDateRange]

  @SpeciesCode int
, @ProposedStartDate date
, @ProposedEndDate date

AS
BEGIN
DECLARE @Return int
IF OBJECT_ID('tempdb..#DateTester') IS NOT NULL DROP TABLE #DateTester
SELECT a.*
INTO #DateTester
FROM
(SELECT 'S' as Flag, s.ActivationDate as CodeDate FROM SpeciesCodes_PacFIN s WHERE s.SpeciesCode = @SpeciesCode
AND NOT isDate(CAST(s.ActivationDate as datetime))=0
UNION ALL
SELECT 'E' as Flag, s.LastUseDate as CodeDate FROM SpeciesCodes_PacFIN s WHERE s.SpeciesCode = @SpeciesCode 
AND NOT isDate(CAST(s.LastUseDate as datetime))=0
UNION ALL
SELECT 'S' as Flag, @ProposedStartDate as CodeDate WHERE NOT isDate(CAST(@ProposedStartDate as datetime))=0
UNION ALL
SELECT 'E' as Flag, @ProposedEndDate as CodeDate WHERE NOT isDate(CAST(@ProposedEndDate as datetime))=0
) a
ORDER BY a.CodeDate ASC
--Build a string from the date ordered Flags column and look for error patterns (SS or EE)
DECLARE @Flags NVARCHAR(100)= ( select ''+ dt.Flag  from #DateTester dt for XML path(''))  --Generates a hyperlink with our flags
DECLARE @SIndex INT = (SELECT CHARINDEX('SS', s.[Flag String]) FROM (SELECT @Flags as [Flag String]) s)-- Hyperlink to an ordinary string and get index
DECLARE @EIndex INT = (SELECT CHARINDEX('EE', s.[Flag String]) FROM (SELECT @Flags as [Flag String]) s)-- Hyperlink to an ordinary string and get index
DECLARE @ENotFirst INT = (SELECT CHARINDEX('E', s.[Flag String]) FROM (SELECT @Flags as [Flag String]) s)-- Hyperlink to an ordinary string and get index
--Last, check to make sure that a start date never coincides with an EndDate (or vice versa)
DECLARE @DateTouch int = CASE WHEN EXISTS (SELECT 1 FROM #DateTester dt INNER JOIN #DateTester dt2 ON dt.CodeDate = dt2.CodeDate
WHERE (dt.Flag='S' AND dt2.Flag='E') OR (dt2.Flag='S' AND dt.Flag='E'))  --This is a small dataset, so this should not be bad
THEN 1 ELSE 0 END
DECLARE @EFirst int = CASE WHEN @ENotFirst = 1 then 1 else 0 end
SET @Return = @SIndex + @EIndex  +@EFirst + @DateTouch --Only a sum of zero means okay
RETURN @Return
END
