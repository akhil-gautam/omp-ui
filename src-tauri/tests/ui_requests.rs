//! How omp's UI requests reach the webview.

use omp_rpc::wire::{
	ExtensionUiRequest, NotifyUiRequest, RpcNotification, SelectUiRequest, SetStatusUiRequest,
	SetWidgetUiRequest,
};
use omp_ui_lib::protocol::from_notification;
use omp_ui_lib::types::EventKind;

#[test]
fn a_question_becomes_a_dialog() {
	let request = RpcNotification::ExtensionUiRequest(ExtensionUiRequest::Select(SelectUiRequest {
		id: "1".to_owned(),
		title: "Approve bash".to_owned(),
		options: vec!["Approve".to_owned(), "Deny".to_owned()],
		option_details: None,
		timeout: None,
	}));

	let event = from_notification("p1", request).expect("a select request becomes a dialog");
	assert_eq!(event.kind, EventKind::UiRequest);
	assert_eq!(event.project_id, "p1");
}

#[test]
fn a_widget_update_does_not_become_a_dialog() {
	// Widgets are fire-and-forget. Showing them as a dialog would leave a
	// modal over the app that the user cannot get rid of.
	let request =
		RpcNotification::ExtensionUiRequest(ExtensionUiRequest::SetWidget(SetWidgetUiRequest {
			id: "1".to_owned(),
			widget_key: "autoresearch".to_owned(),
			widget_lines: None,
			widget_placement: None,
		}));

	assert!(from_notification("p1", request).is_none());
}

#[test]
fn a_notification_becomes_a_notice() {
	let request = RpcNotification::ExtensionUiRequest(ExtensionUiRequest::Notify(NotifyUiRequest {
		id: "1".to_owned(),
		message: "the build finished".to_owned(),
		notify_type: None,
	}));

	let event = from_notification("p1", request).expect("a notice reaches the UI");
	assert_eq!(event.kind, EventKind::Notice);
}

#[test]
fn a_status_line_is_passed_on() {
	let request = RpcNotification::ExtensionUiRequest(ExtensionUiRequest::SetStatus(SetStatusUiRequest {
		id: "1".to_owned(),
		status_key: "main".to_owned(),
		status_text: Some("running the tests".to_owned()),
	}));

	let event = from_notification("p1", request).expect("the status reaches the UI");
	assert_eq!(event.kind, EventKind::StatusText);
}
