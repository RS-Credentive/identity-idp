import { getAssetPath } from '@18f/identity-assets';
import { t } from '@18f/identity-i18n';

function NoInPersonLocationsDisplay({ address }) {
  return (
    <div className="grid-row grid-gap grid-gap-1">
      <img
        className="grid-col-2 margin-top-3"
        alt={t('image_description.info_pin_map')}
        width={65}
        height={64.6}
        src={getAssetPath('info-pin-map.svg')}
      />
      <div className="inline-block grid-col-10">
        <h2 role="status">
          {t('in_person_proofing.body.location.po_search.none_found', { address })}
        </h2>
        <p>{t('in_person_proofing.body.location.po_search.none_found_tip')}</p>
      </div>
    </div>
  );
}

export default NoInPersonLocationsDisplay;
