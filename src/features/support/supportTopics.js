import { Bug, CircleHelp, CreditCard, KeyRound, Lightbulb, Printer, RadioTower, Scale, ScanBarcode, Wifi } from 'lucide-react'

const TOPIC_ICONS = {
  no_signal_pos: Wifi,
  slow_wifi: Wifi,
  repeater_down: RadioTower,
  pos_no_power: CreditCard,
  ticket_printer: Printer,
  scanner_no_read: ScanBarcode,
  scale_no_connect: Scale,
  cant_login: KeyRound,
  app_error: Bug,
  feature_request: Lightbulb,
}

const CATEGORY_ICONS = { network: Wifi, pos: CreditCard, printer: Printer, scanner: ScanBarcode, access: KeyRound, bug: Bug, feature: Lightbulb }

export const topicIcon = (topic) => TOPIC_ICONS[topic?.code] ?? CATEGORY_ICONS[topic?.category] ?? CircleHelp
