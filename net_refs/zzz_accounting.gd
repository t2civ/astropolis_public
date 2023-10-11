# accountingXXX.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************


# Each Player and each Facility has an Accounting.

const ACCOUNT_BALANCE := Enums.AccountClass.ACCOUNT_BALANCE

const REVENUE := Enums.AccountItem.REVENUE
const INC_STMT_GROSS := Enums.AccountItem.INC_STMT_GROSS
const INC_STMT_OPEX := Enums.AccountItem.INC_STMT_OPEX
const INC_STMT_NONOP := Enums.AccountItem.INC_STMT_NONOP
const CF_STMT_OPERATING := Enums.AccountItem.CF_STMT_OPERATING
const CF_STMT_INVESTING := Enums.AccountItem.CF_STMT_INVESTING
const CF_STMT_FINANCING := Enums.AccountItem.CF_STMT_FINANCING
const BAL_SHT_SHORT_TERM := Enums.AccountItem.BAL_SHT_SHORT_TERM
const BAL_SHT_LONG_TERM := Enums.AccountItem.BAL_SHT_LONG_TERM

const INCOME_DEPRECIATION := Enums.AccountItem.INCOME_DEPRECIATION
const INCOME_INTEREST_EXPENSE := Enums.AccountItem.INCOME_INTEREST_EXPENSE
const CASH_FLOW_CAPEX := Enums.AccountItem.CASH_FLOW_CAPEX
const CASH_FLOW_INTEREST := Enums.AccountItem.CASH_FLOW_INTEREST
const CASH_FLOW_NEW_FINANCING := Enums.AccountItem.CASH_FLOW_NEW_FINANCING
const BALANCE_CASH := Enums.AccountItem.BALANCE_CASH
const BALANCE_SHORT_TERM_DEBT := Enums.AccountItem.BALANCE_SHORT_TERM_DEBT
const BALANCE_LONG_TERM_DEBT := Enums.AccountItem.BALANCE_LONG_TERM_DEBT


var optimal_cash_balance := 1e6
var min_cash_balance := -1e6 # if below, convert to long-term debt


var current_year: int

var revenue := 0.0 # positive values of INC_STMT_GROSS
var gross_income := 0.0 # INC_STMT_GROSS
var opex_income := 0.0 # INC_STMT_OPEX (always negative)
var nonop_income := 0.0 # INC_STMT_NONOP
var operating_cshflw := 0.0
var investing_cshflw := 0.0
var financing_cshflw := 0.0
var short_term_balance := 0.0
var long_term_balance := 0.0

var cash_balance := 0.0 # (+) BALANCE_CASH, (-) BALANCE_SHORT_TERM_DEBT
var long_term_debt := 0.0 # BALANCE_LONG_TERM_DEBT

var items := {} # not broken out above; indexed by accounting.tsv row

var history := {} # indexed by accounting.tsv row int

var future_depreciation := [0.0] # never shrinks; 1st 0.0 is terminal value

var _last_interest_update: int # solar day


const PERSIST_MODE := IVEnums.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"optimal_cash_balance",
	&"min_cash_balance",
	&"current_year",
	&"current_month",
	&"revenue",
	&"gross_income",
	&"opex_income",
	&"nonop_income",
	&"operating_cshflw",
	&"investing_cshflw",
	&"financing_cshflw",
	&"short_term_balance",
	&"long_term_balance",
	&"items",
	&"cash_balance",
	&"long_term_debt",
	&"history",
	&"future_depreciation",
	&"_last_interest_update",
]

var _times: Array = IVGlobal.times
var _accounting_helper #: AccountingHelper = IVGlobal.program.AccountingHelper
var _account_class : Array = _accounting_helper.account_class
var _account_section: Array = _accounting_helper.account_section


func add_capital_imporovement(cost: float, depreciation_years: int) -> void:
	assert(cost < 0.0)
	assert(depreciation_years > 1)
	# cash flow
	add_item(cost, -1, CASH_FLOW_CAPEX)
	# future depreciation
	var yearly_depreciation := cost / depreciation_years
	var future_depreciation_size := future_depreciation.size()
	while future_depreciation_size < depreciation_years:
		future_depreciation.append(0.0)
		future_depreciation_size += 1
	var index_year := 0
	while index_year < depreciation_years:
		future_depreciation[index_year] += yearly_depreciation
		index_year += 1
	_refinance()


func add_item(amount: float, income_type: int, cshflw_type: int) -> void:
	# Use specific functions above when applicable. All cash flow items
	# added here impact cash_balance & short_term_balance.
	if income_type != -1:
		var account_section: int = _account_section[income_type]
		match account_section:
			INC_STMT_GROSS:
				if amount > 0.0:
					revenue += amount
				gross_income += amount
			INC_STMT_OPEX:
				opex_income += amount
			INC_STMT_NONOP:
				nonop_income += amount
			_:
				assert(false, "Unknown income_type " + str(income_type))
		var current: float = items.get(income_type, 0.0)
		items[income_type] = current + amount
	if cshflw_type != -1:
		_process_interest()
		var account_section: int = _account_section[cshflw_type]
		match account_section:
			CF_STMT_OPERATING:
				operating_cshflw += amount
			CF_STMT_INVESTING:
				investing_cshflw += amount
			CF_STMT_FINANCING:
				financing_cshflw += amount
			_:
				assert(false, "Unknown cshflw_type " + str(cshflw_type))
		var current: float = items.get(cshflw_type, 0.0)
		items[cshflw_type] = current + amount
		cash_balance += amount
		short_term_balance += amount


func advance_calendar_month() -> void:
	_process_interest()
	_refinance()


func advance_calendar_year(year: int) -> void:
	assert(year == current_year + 1)
	_do_yearly_depreciation()
	_record_and_reset_year()
	current_year = year


func _init(is_loaded_game := true, optimal_cash_balance_ := 1e6, min_cash_balance_ := -1e6) -> void:
	if is_loaded_game:
		return
	optimal_cash_balance = optimal_cash_balance_
	min_cash_balance = min_cash_balance_
	_last_interest_update = int(_times[2])
	history[REVENUE] = []
	history[INC_STMT_GROSS] = []
	history[INC_STMT_OPEX] = []
	history[INC_STMT_NONOP] = []
	history[CF_STMT_OPERATING] = []
	history[CF_STMT_INVESTING] = []
	history[CF_STMT_FINANCING] = []
	history[BAL_SHT_SHORT_TERM] = []
	history[BAL_SHT_LONG_TERM] = []
	history[BALANCE_CASH] = []
	history[BALANCE_SHORT_TERM_DEBT] = []
	history[BALANCE_LONG_TERM_DEBT] = []


func _process_interest() -> void:
	# repeat calls ok; call at intervals and before changes to balances
	var solar_day := int(_times[2])
	if solar_day == _last_interest_update:
		return
	var n_days := solar_day - _last_interest_update
	_last_interest_update = solar_day
	var interest := 0.0
	if cash_balance < 0.0: # short term debt
		interest = cash_balance * pow(1.0 + _accounting_helper.short_term_interest_rate, n_days)
	if long_term_debt:
		interest += long_term_debt * pow(1.0 + _accounting_helper.long_term_interest_rate, n_days)
	if interest:
		add_item(interest, INCOME_INTEREST_EXPENSE, CASH_FLOW_INTEREST)


func _refinance() -> void:
	# repeat calls ok
	if cash_balance > min_cash_balance:
		return
	# convert short-term debt to long-term debt
	var new_financing :=  optimal_cash_balance - cash_balance # positive
	long_term_debt -= new_financing
	long_term_balance -= new_financing
	add_item(new_financing, -1, CASH_FLOW_NEW_FINANCING)


func _do_yearly_depreciation() -> void:
	if future_depreciation[0]:
		add_item(future_depreciation[0], INCOME_DEPRECIATION, -1)
	var size := future_depreciation.size()
	var year_index := 1
	while year_index < size:
		var amount: float = future_depreciation[year_index]
		future_depreciation[year_index - 1] = amount
		if amount == 0.0:
			break
		year_index += 1
	future_depreciation[-1] = 0.0


func _record_and_reset_year() -> void:
	history[REVENUE].append(revenue)
	history[INC_STMT_GROSS].append(gross_income)
	history[INC_STMT_OPEX].append(opex_income)
	history[INC_STMT_NONOP].append(nonop_income)
	history[CF_STMT_OPERATING].append(operating_cshflw)
	history[CF_STMT_INVESTING].append(investing_cshflw)
	history[CF_STMT_FINANCING].append(financing_cshflw)
	history[BAL_SHT_SHORT_TERM].append(short_term_balance)
	history[BAL_SHT_LONG_TERM].append(long_term_balance)
	if cash_balance < 0.0:
		history[BALANCE_CASH].append(0.0)
		history[BALANCE_SHORT_TERM_DEBT].append(cash_balance)
	else:
		history[BALANCE_CASH].append(cash_balance)
		history[BALANCE_SHORT_TERM_DEBT].append(0.0)
	history[BALANCE_LONG_TERM_DEBT].append(long_term_debt)
	for item_type in items:
		if history.has(item_type):
			history[item_type].append(items[item_type])
		else:
			history[item_type] = [items[item_type]]
		# reset accumulators
		if _account_class[item_type] != ACCOUNT_BALANCE:
			history[item_type] = 0.0
	# reset accumulators
	revenue = 0.0
	gross_income = 0.0
	opex_income = 0.0
	nonop_income = 0.0
	operating_cshflw = 0.0
	investing_cshflw = 0.0
	financing_cshflw = 0.0
