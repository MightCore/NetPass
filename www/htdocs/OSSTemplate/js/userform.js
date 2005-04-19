// userform.js

function userform_changeToUser(o) {
	var RN = "userform_changeToUser";

	dbg(1, RN);

	var gl  = document.getElementById('GroupList');
	var agl = document.getElementById('AvailableGroupList');

	// figure out what's been selected.

	var selectedUser = undefined; 

	userform_unHighLight("AvailableGroupList");

	for (var i = 0 ; i < o.options.length ; i++) {
		if (o.options[i].selected && i == 0) {
			// IE doesnt support <option disabled>
			// deselected if selected and return.
			//http://msdn.microsoft.com/workshop/author/dhtml/reference/properties/disabled_3.asp
			o.options[i].selected = false;
			return;
		}
		if (o.options[i].selected) {
			selectedUser = o.options[i];
			break;
		}
	}

	if (selectedUser == undefined) {
		dbg (1, RN + ": no user selected?");
		return;
	}

	if (gl && agl && (userhash[selectedUser.value] != undefined) ) {
		// unhighlight the GroupList and AccessControlList

		var glo;
		for (var i = gl.options.length-1 ; i ; i--) {
			glo = gl.options[i];
			if (glo) {
				dbg(1, RN + ": " + gl.options.length + 
				    " move to availble: options["+i+"] " + glo.value);
				glo.selected = false;
				if (browserType_IE) gl.options[i] = null;
				agl.options[agl.options.length] = glo;
			} else {
				dbg(1, RN + ": " + gl.options.length + 
				    " move to available: NULL options["+i+"]");
			}
		}

		dbg(1, RN + ": unhighlight ACL");

		userform_unHighLight("AccessControlList");

		// populate the grouplist with the currently
		// selected user's groups, removing them from the
		// availablegrouplist

		var mygroup;
		for(mygroup in userhash[selectedUser.value]) {
			dbg (1, RN + ": move from available: mygroup = " + mygroup);

			for (var i = agl.options.length-1 ; i ; i--) {
				if (agl.options[i].value == mygroup) {
					dbg(1, RN + ": inside "  + gl.options.length );
					if (browserType_IE) {
						var old = agl.options[i];
						agl.options[i] = null;
						gl.options[gl.options.length] = old;
					} else {
						gl.options[gl.options.length] = agl.options[i];
					}
				}
			}
		}
	} else {
		dbg (1, RN + ": one of: gl || agl || userhash["+selectedUser.value+"] is undef");
	}
}

function userform_editACL(o) {
	if (o) {
		var user = userform_lookupSelectedUser();
		if (o.selected) {
			// add o.value to user
		}
	}
}

/* determine who the currently selected user is */

function userform_saveUserSettings(o) {
	dbg(1, "save user");
	var ul = document.getElementById('UserList');
	if (o && ul) {
		for (var i = 0 ; i < ul.options.length ; i++) {
			if (ul.options[i].selected) {
				dbg(1, ul.options[i].value + " was selected");
			}
		}
	}
}

function userform_lookupSelectedUser() {
	var RN = "userform_lookupSelectedUser";
	var ul = document.getElementById('UserList');
	if (ul) {
		for (var i = 1 ; i < ul.length ; i++) {
			if (ul.options[i].selected)
				return ul.options[i].value;
		}
	} else {
		dbg (1, RN + ": error, cant find UserList object");
	}
	return undef;
}

function userform_unHighLight(oname, item) {
	var RN  = "userform_unHighLightACL";
	if (oname == undefined) oname = "AccessControlList";

	var acl = document.getElementById(oname);
	if (acl) {
		for(var i = 1 ; i < acl.options.length ; i++) {
			if (item) {
				if (item == acl.options[i].value)
					acl.options[i].selected = false;
			} else {
				acl.options[i].selected = false;
			}
		}
	} else {
		dbg (1, RN + ": error cant find " + oname + " object");
	}
}

function userform_highLight(oname, item) {
	var RN  = "userform_highLightACL";
	if (oname == undefined) oname = "AccessControlList";
	var acl = document.getElementById(oname);
	if (acl) {
		for(var i = 1 ; i < acl.options.length ; i++) {
			//dbg (1, RN + ": " + acl.options[i].value + " == " + item + "?");
			if (item) {
				if (acl.options[i].value == item)
					acl.options[i].selected = true;
			} 
			else {
				acl.options[i].selected = true;
			}
		}
	} else {
		dbg (1, RN + ": error cant find " + oname + " object");
	}
}


function userform_disableList(oname) {
	var RN  = "userform_disableList";

	var l = document.getElementById(oname);
	if (l) {
		for(var i = 1 ; i < l.options.length ; i++) {
			l.options[i].selected = false;
			l.options[i].disabled = true;
		}
	} else {
		dbg (1, RN + ": error cant find " + oname + " object");
	}
}

function userform_enableList(oname) {
	var RN  = "userform_enableList";

	var l = document.getElementById(oname);
	if (l) {
		for(var i = 1 ; i < l.options.length ; i++) {
			l.options[i].disabled = false;
		}
	} else {
		dbg (1, RN + ": error cant find " + oname + " object");
	}
}

function userform_onchange_availableGroups() {
	userform_unHighLight("GroupList");
	userform_unHighLight("AccessControlList");
	userform_disableList("AccessControlList");
}

function userform_enableModAll() {
	var RN = "userform_enableModAll";
	dbg(1, RN);
	var o = document.getElementById("addToAll");
	if (o) o.disabled = false;
	else  dbg(1, RN + ": cant find addToAll object");
	o = document.getElementById("remFromAll");
	if (o) o.disabled = false;
	else  dbg(1, RN + ": cant find remFromAll object");
}

function userform_disableModAll() {
	var RN = "userform_disableModAll";
	dbg(1, RN);
	var o = document.getElementById("addToAll");
	if (o) o.disabled = true;
	else  dbg(1, RN + ": cant find addToAll object");
	o = document.getElementById("remFromAll");
	if (o) o.disabled = true;
	else  dbg(1, RN + ": cant find remFromAll object");
}

/* userform_showACLforGroup(o)
 * 
 * this routine is called when there's a change to the
 * GroupList menu. if only one group is selected, we will
 * highlight the Access Types enabled for this group
 * (in the AccessControlList menu. if more than one group is 
 * selected, we will deselect and disable all entries in the 
 * AccessControlList menu. 
 */

function userform_showACLforGroup(o) {
	var RN = "userform_showACLforGroup";
	var su = userform_lookupSelectedUser();

	userform_unHighLight("AccessControlList");
	userform_unHighLight("AvailableGroupList");
	userform_enableList("AccessControlList");

	if (o && su && userhash[su][o.value]) {

		// figure out if there are multiple groups selected
		var selected = 0;
		for (var i = 0 ; i < o.options.length ; i++) {
			if (o.options[i].selected) {
				if (i == 0) {
					// IE doesnt support <option disabled>
					// deselect if selected
					//http://msdn.microsoft.com/workshop/author/dhtml/reference/properties/disabled_3.asp
					o.options[0].selected = false;
				} else {
					selected++;
				}
			}
		}

		if (selected == 0) return;

		if (selected > 1) {
			// clear the ACL and enable the modify all 
			// buttons
			userform_unHighLight("AccessControlList");
			userform_enableModAll();
		}
		else {
			for(var acl in userhash[su][o.value]) {
				userform_disableModAll();
				dbg(1, RN + ": acl/"+su+"/"+o.value+"="+acl);
				userform_highLight("AccessControlList", acl);
			} 
		}
	}
}

/* userform_addGroupToUser()
 * flip over the groups in the AvailableGroupList and move
 * any that are selected to the GroupList. at the same time, 
 * create the appropriate entries in the userhash.
 */

function userform_addGroupToUser() {
	var RN  = "userform_addGroupToUser";
	var su  = userform_lookupSelectedUser();
	var agl = document.getElementById('AvailableGroupList');
	var gl  = document.getElementById('GroupList');
	if (agl && gl) {
		for (var i = agl.options.length-1 ; i > 0 ; i--) {
			dbg (1, RN + ": move agl/" + i + " to gl");
			if (agl.options[i].selected) {
				var opt = agl.options[i];
				gl.options[gl.options.length] = opt;
				userhash[su][opt.value] = new Object;
			}
		}
	} else {
		dbg (1, RN + ": cant find AvailableGroupList and/or GroupList object");
	}
	return false;
}

function userform_remGroupFromUser() {
	var RN = "userform_remGroupFromUser";
	var su = userform_lookupSelectedUser();
	var agl = document.getElementById('AvailableGroupList');
	var gl  = document.getElementById('GroupList');
	if (agl && gl) {
		for (var i = gl.options.length-1 ; i > 0 ; i--) {
			dbg (1, RN + ": move gl/" + i + " to agl");
			if (gl.options[i].selected) {
				var opt = gl.options[i];
				agl.options[agl.options.length] = opt;
				delete userhash[su][opt.value];
			}
		}
	} else {
		dbg (1, RN + ": cant find AvailableGroupList and/or GroupList object");
	}
	return false;
}


function userform_onfocus_addUser(o) {
	var RN = "userform_onfocus_addUser";
	dbg (1, RN);

	if (o && o.value == "Add user...") o.value = "";
}

function userform_onblur_addUser(o) {
	var RN = "userform_onblur_addUser";
	dbg (1, RN);

	if (userhash[o.value] != undefined) {
		dbg(1, RN + ": user " + o.value + " already exists");
		return;
	}

	if (o && o.value == "") o.value = "Add user...";
	if (o && o.value == "Add user...") return;

	var ul = document.getElementById('UserList');
	if (!ul) {
		dbg(1, RN + ": cant find UserList object");
		return;
	}

	userhash[o.value] = new Object();
	var no = new Option(o.value, o.value, false, false);
	ul.options[ul.options.length] = no;
}
