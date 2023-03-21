# table_reader.gd
# This file is part of Astropolis
# Copyright 2019-2023 Charlie Whitfield, all rights reserved
# *****************************************************************************
class_name TableReader
extends IVTableReader



func get_type_by_type(table_name: String) -> Array:
	return _tables[table_name]


func get_type_by_type_row(table_name: String, row: int) -> Array:
	return _tables[table_name][row]

