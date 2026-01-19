clear all
set more off

************************************************************
* STEP 1. Import and basic prep
************************************************************

import delimited "/Users/delaneythau/Downloads/wb_data.csv", clear

* Keep ONLY treated + final control country
keep if inlist(destination_name, "Nigeria", "Egypt, Arab Rep.")

* Build quarterly time variable from 'period' (e.g. "2024_4Q")
gen year = real(substr(period, 1, 4))
gen qtr  = real(substr(period, 6, 1))
gen tq   = yq(year, qtr)
format tq %tq

************************************************************
* STEP 2. Make cost & speed numeric, then collapse
************************************************************

* Numeric speed (extract number from strings like "3", "3.5", "3 days")
gen double speed_num = .
replace speed_num = real(regexs(1)) if regexm(speedactual, "([0-9]+\.?[0-9]*)")

* Numeric cost
capture confirm numeric variable cc1totalcost
if _rc {
    destring cc1totalcost, gen(cost_num) ignore(" ,%")
}
else {
    gen double cost_num = cc1totalcost
}

* Collapse to one obs per country-quarter (average across corridors/providers)
collapse (mean) cost_num speed_num, ///
    by(destination_name tq year qtr)

rename cost_num    cost
rename speed_num   speedactual

************************************************************
* STEP 3. Panel setup + DID variables (Nigeria vs Egypt only)
************************************************************

encode destination_name, gen(country_id)
xtset country_id tq

* Nigeria is treated (Egypt is control)
gen treated = (destination_name == "Nigeria")

* Post = from 2023q4 onwards (Nigeria lifts crypto ban)
gen post = (tq >= tq(2023q4))

tab destination_name treated
tab year post if inrange(year, 2020, 2025)

************************************************************
* STEP 4. DID regressions: COST and SPEED
************************************************************

* Cost
xtreg cost i.post##i.treated i.tq, fe cluster(country_id)
boottest 1.post#1.treated, cluster(country_id) reps(9999) seed(12345)


xtreg cost i.post##i.treated i.tq, fe cluster(country_id)

* Wild cluster bootstrap (Webb weights) for the DID term
boottest 1.post#1.treated, cluster(country_id) weight(webb) reps(9999)


* Speed 
xtreg speedactual i.post##i.treated i.tq, fe cluster(country_id)
boottest 1.post#1.treated, cluster(country_id) reps(9999) seed(12345)

xtreg speedactual i.post##i.treated i.tq, fe cluster(country_id)

boottest 1.post#1.treated, cluster(country_id) weight(webb) reps(9999)



************************************************************
* STEP 6. PRE-TREND GRAPHS (Nigeria vs Egypt only)
************************************************************

* Cost pre-trend (pre-2023 only)
preserve
keep if inrange(year, 2018, 2022)

twoway ///
    (line cost tq if destination_name=="Nigeria",       lcolor(blue)  lwidth(medthick)) ///
    (line cost tq if destination_name=="Egypt, Arab Rep.", lcolor(red)   lwidth(medthick) lpattern(dash)) ///
    , ///
	yscale(range(0 10)) ///
    ylabel(0(2)10) ///
    legend(order(1 "Nigeria" 2 "Egypt")) ///
    xtitle("Quarter") ///
    ytitle("Average remittance cost") ///
    title("Pre-Trends: Cost of Receiving Remittances (Nigeria vs Egypt)")

restore

* Speed pre-trend (pre-2023 only)
preserve
keep if inrange(year, 2018, 2022)

twoway ///
    (line speedactual tq if destination_name=="Nigeria",       lcolor(blue)  lwidth(medthick)) ///
    (line speedactual tq if destination_name=="Egypt, Arab Rep.", lcolor(red)   lwidth(medthick) lpattern(dash)) ///
    , ///
	yscale(range(0 4)) ///
    ylabel(0(1)4) ///
    legend(order(1 "Nigeria" 2 "Egypt")) ///
    xtitle("Quarter") ///
    ytitle("Average remittance speed") ///
    title("Pre-Trends: Speed of Receiving Remittances (Nigeria vs Egypt)")

restore

************************************************************
* STEP 7. DID GRAPH (COST): Actual, Counterfactual, Egypt
************************************************************

preserve
keep if year >= 2020

* Build separate Nigeria and Egypt series
gen group = cond(treated==1, "Nigeria", "Egypt")
collapse (mean) cost, by(group tq)

reshape wide cost, i(tq) j(group) string
* Variables now: costNigeria  costEgypt

* Shock quarter
local shock = tq(2023q4)

* Levels at the shock
summ costNigeria if tq==`shock'
local baseNig = r(mean)

summ costEgypt if tq==`shock'
local baseEgy = r(mean)

* Counterfactual Nigeria path based on Egypt's trend
gen counterfactual = `baseNig' + (costEgypt - `baseEgy')
replace counterfactual = . if tq < `shock'

twoway ///
    (line costNigeria    tq, lwidth(medthick) lcolor(blue)) ///
    (line counterfactual tq, lpattern(dash)   lwidth(medthick) lcolor(red)) ///
    (line costEgypt      tq, lpattern(dot)    lwidth(medthick) lcolor(black)) ///
    , ///
    xline(`shock', lpattern(shortdash) lcolor(black)) ///
    legend(order(1 "Nigeria (actual)" 2 "Nigeria (counterfactual)" 3 "Egypt (control)")) ///
    xtitle("Quarter") ///
    ytitle("Average remittance cost") ///
    title("DID: Cost of Receiving Remittances (Nigeria vs Egypt)") ///
    note("Vertical line: Nigeria lifts crypto ban (2023Q4)")

restore

************************************************************
* STEP 8. DID GRAPH (SPEED): Actual, Counterfactual, Egypt
************************************************************

preserve
keep if year >= 2020

gen group = cond(treated==1, "Nigeria", "Egypt")
collapse (mean) speedactual, by(group tq)

reshape wide speedactual, i(tq) j(group) string
* Variables now: speedactualNigeria  speedactualEgypt

local shock = tq(2023q4)

summ speedactualNigeria if tq==`shock'
local baseNig = r(mean)

summ speedactualEgypt if tq==`shock'
local baseEgy = r(mean)

gen counterfactual = `baseNig' + (speedactualEgypt - `baseEgy')
replace counterfactual = . if tq < `shock'

twoway ///
    (line speedactualNigeria    tq, lwidth(medthick) lcolor(blue)) ///
    (line counterfactual        tq, lpattern(dash)   lwidth(medthick) lcolor(red)) ///
    (line speedactualEgypt      tq, lpattern(dot)    lwidth(medthick) lcolor(black)) ///
    , ///
	yscale(range(1 4)) ///
    ylabel(1 2 3 4) ///
    xline(`shock', lpattern(shortdash) lcolor(black)) ///
    legend(order(1 "Nigeria (actual)" 2 "Nigeria (counterfactual)" 3 "Egypt (control)")) ///
    xtitle("Quarter") ///
    ytitle("Average remittance speed") ///
    title("DID: Speed of Receiving Remittances (Nigeria vs Egypt)") ///
    note("Vertical line: Nigeria lifts crypto ban (2023Q4)")

restore



