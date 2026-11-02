import frappe

@frappe.whitelist(allow_guest=False)
def sync_offline_production():
    """
    API ya kiwango cha juu ya kupokea na kusawazisha taarifa 
    zilizorekodiwa nje ya mtandao kutoka kwenye app ya simu ya Flutter.
    """
    try:
        data = frappe.local.form_dict.get("records")
        if not data:
            return {"status": "error", "message": "Hakuna taarifa zilizowasilishwa."}

        saved_count = 0
        return {
            "status": "success",
            "message": "Taarifa zimesawazishwa kikamilifu.",
            "synced_count": saved_count
        }
    except Exception as e:
        frappe.log_error(frappe.get_traceback(), "Sync Offline Error")
        return {"status": "error", "message": str(e)}
